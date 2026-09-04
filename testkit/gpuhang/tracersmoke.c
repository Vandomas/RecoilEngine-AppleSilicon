/*
 * Proves the lifetime tracer sees a real early free: submits a long chain of copies between
 * two buffers, then destroys the source while the copies still run. With MVK_TRACE_LIFETIME=1
 * the tracer must print a RELEASED IN FLIGHT report for that buffer before the queue drains.
 */
#include <vulkan/vulkan.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define OK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { printf("FAILED %s -> %d at line %d\n", #x, r_, __LINE__); fflush(stdout); return 2; } } while (0)

static VkPhysicalDevice phys;
static VkDevice dev;

static int make_buffer(VkDeviceSize size, VkBuffer *buf, VkDeviceMemory *mem)
{
    VkBufferCreateInfo bci = {VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
    bci.size = size;
    bci.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    OK(vkCreateBuffer(dev, &bci, NULL, buf));
    VkMemoryRequirements mr;
    vkGetBufferMemoryRequirements(dev, *buf, &mr);
    VkPhysicalDeviceMemoryProperties mp;
    vkGetPhysicalDeviceMemoryProperties(phys, &mp);
    uint32_t mt = UINT32_MAX;
    for (uint32_t i = 0; i < mp.memoryTypeCount; i++)
        if ((mr.memoryTypeBits & (1u << i)) && (mp.memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)) { mt = i; break; }
    VkMemoryAllocateInfo mai = {VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    mai.allocationSize = mr.size; mai.memoryTypeIndex = mt;
    OK(vkAllocateMemory(dev, &mai, NULL, mem));
    OK(vkBindBufferMemory(dev, *buf, *mem, 0));
    return 0;
}

int main(void)
{
    VkApplicationInfo ai = {VK_STRUCTURE_TYPE_APPLICATION_INFO};
    ai.apiVersion = VK_API_VERSION_1_2;
    const char *iexts[] = {"VK_KHR_portability_enumeration"};
    VkInstanceCreateInfo ici = {VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    ici.pApplicationInfo = &ai; ici.enabledExtensionCount = 1; ici.ppEnabledExtensionNames = iexts;
    ici.flags = VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    VkInstance inst;
    OK(vkCreateInstance(&ici, NULL, &inst));
    uint32_t n = 1;
    OK(vkEnumeratePhysicalDevices(inst, &n, &phys));
    float pri = 1.0f;
    VkDeviceQueueCreateInfo dq = {VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
    dq.queueFamilyIndex = 0; dq.queueCount = 1; dq.pQueuePriorities = &pri;
    const char *dexts[] = {"VK_KHR_portability_subset"};
    VkDeviceCreateInfo dci = {VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
    dci.queueCreateInfoCount = 1; dci.pQueueCreateInfos = &dq;
    dci.enabledExtensionCount = 1; dci.ppEnabledExtensionNames = dexts;
    OK(vkCreateDevice(phys, &dci, NULL, &dev));
    VkQueue queue;
    vkGetDeviceQueue(dev, 0, 0, &queue);

    const VkDeviceSize big = 256u << 20;
    VkBuffer a, b; VkDeviceMemory ma, mb;
    if (make_buffer(big, &a, &ma)) return 2;
    if (make_buffer(big, &b, &mb)) return 2;

    VkCommandPoolCreateInfo cpi = {VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    VkCommandPool pool;
    OK(vkCreateCommandPool(dev, &cpi, NULL, &pool));
    VkCommandBufferAllocateInfo cai = {VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    cai.commandPool = pool; cai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY; cai.commandBufferCount = 1;
    VkCommandBuffer cb;
    OK(vkAllocateCommandBuffers(dev, &cai, &cb));
    VkCommandBufferBeginInfo bi = {VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    OK(vkBeginCommandBuffer(cb, &bi));
    VkBufferCopy region = {0, 0, big};
    VkMemoryBarrier mbar = {VK_STRUCTURE_TYPE_MEMORY_BARRIER};
    mbar.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; mbar.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT | VK_ACCESS_TRANSFER_WRITE_BIT;
    for (int c = 0; c < 48; c++) {
        vkCmdCopyBuffer(cb, (c & 1) ? b : a, (c & 1) ? a : b, 1, &region);
        vkCmdPipelineBarrier(cb, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 1, &mbar, 0, NULL, 0, NULL);
    }
    OK(vkEndCommandBuffer(cb));

    VkSubmitInfo si = {VK_STRUCTURE_TYPE_SUBMIT_INFO};
    si.commandBufferCount = 1; si.pCommandBuffers = &cb;
    OK(vkQueueSubmit(queue, 1, &si, VK_NULL_HANDLE));
    printf("submitted 48 copies of 256 MB, now destroying the source while they run\n"); fflush(stdout);
    vkDestroyBuffer(dev, a, NULL);
    vkFreeMemory(dev, ma, NULL);
    printf("source destroyed, the tracer should have reported it above; draining the queue\n"); fflush(stdout);
    VkResult r = vkQueueWaitIdle(queue);
    printf("queue drained -> %d\n", r); fflush(stdout);
    return 0;
}
