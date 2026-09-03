/* This file is part of the Spring engine (GPL v2 or later), see LICENSE.html */

#include <cassert>
#include <cstdarg>
#include <cstring>
#include <cstdint>

#include <algorithm>
#include <array>
#include <mutex>

#include "Backend.h"
#include "Level.h"
#include "DefaultFilter.h"
#include "LogUtil.h"
#include "System/MainDefines.h"

#define MAX_LOG_SINKS 8

namespace log_formatter {
	static std::array<log_sink_ptr, MAX_LOG_SINKS> sinks = {{nullptr}};
	static std::array<log_cleanup_ptr, MAX_LOG_SINKS> cleanupFuncs = {{nullptr}};

	static size_t numSinks = 0;
	static size_t numFuncs = 0;

	template<typename T, size_t S> bool array_insert(std::array<T, S>& array, T value, size_t& count) {
		const auto iter = std::find(array.begin(), array.end(), nullptr);

		// too many elems
		if (iter == array.end())
			return false;
		// check for duplicates
		// NOLINTNEXTLINE{readability-simplify-boolean-expr}
		if (false && std::find(array.begin(), array.end(), value) != array.end())
			return false;

		return (*iter = value, ++count);
	}
	template<typename T, size_t S> bool array_remove(std::array<T, S>& array, T value, size_t& count) {
		const auto iter = std::find(array.begin(), array.end(), value);

		if (iter == array.end())
			return false;

		// remove without leaving holes
		for (size_t i = iter - array.begin(), j = array.size() - 1; i < j; i++) {
			array[i] = array[i + 1];
		}

		return (array[--count] = nullptr, true);
	}


	bool insert_sink(log_sink_ptr sink) {
		return (array_insert(sinks, sink, numSinks));
	}
	bool remove_sink(log_sink_ptr sink) {
		return (array_remove(sinks, sink, numSinks));
	}

	bool insert_func(log_cleanup_ptr func) {
		return (array_insert(cleanupFuncs, func, numFuncs));
	}
	bool remove_func(log_cleanup_ptr func) {
		return (array_remove(cleanupFuncs, func, numFuncs));
	}

	// Route a fully-formatted message to every registered sink.
	void emit_to_sinks(int level, const char* section, const char* msg) {
		for (size_t i = 0; i < numSinks; i++) {
			assert(sinks[i] != nullptr);
			sinks[i](level, section, msg);
		}
	}
}


// ---------------------------------------------------------------------------
// Generic near-identical repeat coalescing (bounds infolog.txt growth).
//
// Motivation: high-frequency lines — per-event input diagnostics
// (SPRING_DBG_INPUT), the per-stall "[stall] draw gap" warning, and any future
// per-frame message — can bloat the single infolog.txt to hundreds of MB over
// a long session, making it useless as a bug-report attachment. Instead of a
// separate diagnostics file or per-source throttles, floods are collapsed HERE,
// at the one choke point every record passes through, so the guarantee covers
// ALL sources uniformly.
//
// Mechanism: each record's formatted message is reduced to a "signature" by
// collapsing every run of digits to a single '#' (so "[input] pos=100,200" and
// "[input] pos=101,201" share one signature). The FIRST occurrence of a
// signature is always written in full. While the SAME signature keeps arriving
// consecutively the duplicates are suppressed and counted; a rollup line
// ("[log] previous line repeated N more time(s) ...") is emitted every
// ROLLUP_EVERY suppressed lines, again when a different line breaks the run, and
// once more at shutdown — so the count is never lost and the reporter sees
// totals. Distinct/rare lines (errors, the startup <User Config> dump, one-off
// warnings) have distinct signatures and are never suppressed. With the debug
// gates off there is nothing to coalesce, so default behavior is unchanged.
namespace log_coalesce {
	// One rollup emitted per this many suppressed duplicates (keeps a long flood
	// visibly "live" while bounding rollup volume itself).
	static constexpr uint64_t ROLLUP_EVERY = 100;
	// How many DISTINCT recent flood patterns can be collapsed concurrently. A
	// single-slot ("last line") design would fail when two high-frequency
	// sources interleave (e.g. per-event [input] bursts alternating with a
	// per-frame [stall] warning) — each would break the other's run. Tracking
	// the last few patterns lets them all collapse. 8 comfortably covers the
	// engine's simultaneous flood sources (input/stall/config/...).
	static constexpr size_t NUM_SLOTS = 8;

	struct Slot {
		char     sig[512];
		char     section[64];
		int      level;
		uint64_t sinceRollup; // suppressed for this pattern since its last rollup
		uint64_t seq;         // for LRU eviction (higher = more recently touched)
		bool     used;
	};

	static std::mutex mutex;
	static Slot       slots[NUM_SLOTS] = {};
	static uint64_t   seqCounter = 0;

	// Reduce (section, message) to a signature: the section, a separator, then
	// the message with each varying numeric token collapsed to a single '#'.
	//
	// A "numeric token" is a maximal run of digits together with the separators
	// that appear INSIDE numeric fields — sign, decimal point, and thousands /
	// coordinate comma ("-1,-2", "160.0", "300,174", "0x1F"→"#x#"). A run is
	// collapsed only if it contains at least one digit, so lone punctuation (the
	// "->" in a config line, a bare '-') is kept verbatim and distinct lines stay
	// distinct. This is what lets per-event lines whose only difference is their
	// (possibly negative, possibly fractional) numbers share one signature.
	static void MakeSig(const char* section, const char* msg, char* out, size_t outSz) {
		size_t o = 0;
		for (const char* s = (section != nullptr) ? section : ""; *s != '\0' && o + 1 < outSz; ++s)
			out[o++] = *s;
		if (o + 1 < outSz)
			out[o++] = '\x1f'; // section / message separator

		const char* p = msg;
		while (*p != '\0' && o + 1 < outSz) {
			const char* start = p;
			bool sawDigit = false;
			for (; *p != '\0'; ++p) {
				const char c = *p;
				if (c >= '0' && c <= '9') { sawDigit = true; continue; }
				if (c == '.' || c == ',' || c == '+' || c == '-') continue;
				break;
			}
			if (p != start && sawDigit) {
				out[o++] = '#';
			} else if (p != start) {
				// punctuation-only run: keep it (bounded)
				for (const char* q = start; q < p && o + 1 < outSz; ++q)
					out[o++] = *q;
			} else {
				out[o++] = *p++;
			}
		}
		out[o] = '\0';
	}

	static void FormatRollup(char* buf, size_t bufSz, uint64_t n, const char* section) {
		snprintf(buf, bufSz, "[log] previous line repeated %llu more time(s) [section: %s]",
			(unsigned long long)n, section);
	}
}


#ifdef __cplusplus
extern "C" {
#endif


// note: no real point to TLS, sinks themselves are not thread-safe
static _threadlocal log_record_t cur_record = {{0}, "", "",  0, 0};
static _threadlocal log_record_t prv_record = {{0}, "", "",  0, 0};


extern void log_formatter_format(log_record_t* log, va_list arguments);

void log_backend_registerSink(log_sink_ptr sink) { log_formatter::insert_sink(sink); }
void log_backend_unregisterSink(log_sink_ptr sink) { log_formatter::remove_sink(sink); }

void log_backend_registerCleanup(log_cleanup_ptr cleanupFunc) { log_formatter::insert_func(cleanupFunc); }
void log_backend_unregisterCleanup(log_cleanup_ptr cleanupFunc) { log_formatter::remove_func(cleanupFunc); }


/**
 * @name logging_backend
 * ILog.h backend implementation.
 */
///@{

// formats and routes the record to all sinks
void log_backend_record(int level, const char* section, const char* fmt, va_list arguments)
{
	if (log_formatter::numSinks == 0)
		return;

	cur_record.sec = section;
	cur_record.fmt = fmt;
	cur_record.lvl = level;

	// format the record
	log_formatter_format(&cur_record, arguments);

	// check for duplicates after formatting; can not be
	// done in log_frontend_record or log_filter_record
	const int cmp = (prv_record.msg[0] != 0 && STRCASECMP(cur_record.msg, prv_record.msg) == 0);

	cur_record.cnt += cmp;
	cur_record.cnt *= cmp;

	if (const auto limit = log_filter_getRepeatLimit(); limit && cur_record.cnt >= limit)
		return;

	// Generic near-identical coalescing. Decide under the lock but emit OUTSIDE
	// it: a sink may re-enter the logger (e.g. FileSink logs an error on a failed
	// fopen), and holding the mutex across the sink call would deadlock.
	bool emitRecord = true;
	bool emitRollup = false;
	// the rollup is bookkeeping for the log file, not something a player needs to
	// read in the in-game console, so it goes out at debug level
	int  rollupLevel = LOG_LEVEL_DEBUG;
	char rollupMsg[192] = {0};
	char rollupSection[64] = {0};
	// stack frames differ only in their numbers, so the signature folds a whole
	// trace into one line and the watchdog or crash dump loses everything but
	// its first frame. never coalesce that section
	const bool isStackTrace = (section != nullptr && strcmp(section, "CrashHandler") == 0);
	if (!isStackTrace) {
		using namespace log_coalesce;
		char sig[sizeof(Slot::sig)];
		MakeSig(section, cur_record.msg, sig, sizeof(sig));

		std::lock_guard<std::mutex> lck(mutex);

		// look for this pattern among the recently-seen ones
		Slot* match = nullptr;
		for (auto& s: slots) {
			if (s.used && strcmp(s.sig, sig) == 0) { match = &s; break; }
		}

		if (match != nullptr) {
			// near-identical to a recent line: suppress, count, roll up periodically
			emitRecord = false;
			match->seq = ++seqCounter;
			if (++match->sinceRollup >= ROLLUP_EVERY) {
				FormatRollup(rollupMsg, sizeof(rollupMsg), match->sinceRollup, match->section);
				memcpy(rollupSection, match->section, sizeof(rollupSection));
				emitRollup = true;
				match->sinceRollup = 0;
			}
		} else {
			// a new/distinct line: it passes through in full. Claim a slot (free,
			// else least-recently-used); if we evict a pattern with a pending
			// tail, flush its rollup first so its count is not lost.
			Slot* victim = &slots[0];
			for (auto& s: slots) {
				if (!s.used) { victim = &s; break; }
				if (s.seq < victim->seq) victim = &s;
			}
			if (victim->used && victim->sinceRollup > 0) {
				FormatRollup(rollupMsg, sizeof(rollupMsg), victim->sinceRollup, victim->section);
				memcpy(rollupSection, victim->section, sizeof(rollupSection));
				emitRollup = true;
			}
			memcpy(victim->sig, sig, sizeof(victim->sig));
			std::strncpy(victim->section, (section != nullptr) ? section : "", sizeof(victim->section) - 1);
			victim->section[sizeof(victim->section) - 1] = '\0';
			victim->level = level;
			victim->sinceRollup = 0;
			victim->seq = ++seqCounter;
			victim->used = true;
		}
	}

	if (emitRollup)
		log_formatter::emit_to_sinks(rollupLevel, rollupSection, rollupMsg);

	if (!emitRecord)
		return;

	// sink the record into each registered sink
	log_formatter::emit_to_sinks(level, section, cur_record.msg);

	if (cur_record.cnt > 0)
		return;

	memcpy(prv_record.msg, cur_record.msg, sizeof(cur_record.msg));
}

/// Emit any pending coalesced-repeat tail (so the last flood's residual count
/// is not lost). Called from log_backend_cleanup() — i.e. at LOG_CLEANUP() and,
/// via the atexit flush, at normal shutdown.
void log_backend_flushRepeats() {
	using namespace log_coalesce;

	struct Pending { int level; char section[64]; char msg[192]; };
	Pending pend[NUM_SLOTS];
	size_t  n = 0;
	{
		std::lock_guard<std::mutex> lck(mutex);
		for (auto& s: slots) {
			if (!s.used || s.sinceRollup == 0)
				continue;
			pend[n].level = s.level;
			memcpy(pend[n].section, s.section, sizeof(pend[n].section));
			FormatRollup(pend[n].msg, sizeof(pend[n].msg), s.sinceRollup, s.section);
			s.sinceRollup = 0;
			++n;
		}
	}
	for (size_t i = 0; i < n; i++)
		log_formatter::emit_to_sinks(pend[i].level, pend[i].section, pend[i].msg);
}

/// Passes on a cleanup request to all sinks
void log_backend_cleanup() {
	log_backend_flushRepeats();

	const auto& funcs = log_formatter::cleanupFuncs;

	for (size_t i = 0; i < log_formatter::numFuncs; i++) {
		assert(funcs[i] != nullptr);
		funcs[i]();
	}
}

///@}

#ifdef __cplusplus
} // extern "C"
#endif

