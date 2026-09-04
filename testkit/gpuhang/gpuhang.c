/*
 * Hangs the gpu on purpose with a compute shader that counts to 2^32, then reports what the
 * process sees. With MVK_EXIT_ON_DEVICE_LOSS=1 MoltenVK is expected to end the process with
 * code 70 from its completion handler; without it the loss surfaces as VK_ERROR_DEVICE_LOST
 * and this program exits 3 on its own.
 */
#include <vulkan/vulkan.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include "hang_spv.h"

#define OK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { printf("FAILED %s -> %d at line %d\n", #x, r_, __LINE__); fflush(stdout); return 2; } } while (0)

static double now_ms(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec*1000.0+t.tv_nsec/1e6;}

int main(void)
{
    VkApplicationInfo ai = {VK_STRUCTURE_TYPE_APPLICATION_INFO};
    ai.apiVersion = VK_API_VERSION_1_2;
    const char *iexts[] = {"VK_KHR_portability_enumeration"};
    VkInstanceCreateInfo ici = {VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    ici.pApplicationInfo = &ai;
    ici.enabledExtensionCount = 1;
    ici.ppEnabledExtensionNames = iexts;
    ici.flags = VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    VkInstance inst;
    OK(vkCreateInstance(&ici, NULL, &inst));
    uint32_t n = 1;
    VkPhysicalDevice phys;
    OK(vkEnumeratePhysicalDevices(inst, &n, &phys));

    uint32_t qn = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(phys, &qn, NULL);
    VkQueueFamilyProperties qp[8];
    if (qn > 8) qn = 8;
    vkGetPhysicalDeviceQueueFamilyProperties(phys, &qn, qp);
    uint32_t qfam = 0;
    for (uint32_t i = 0; i < qn; i++) if (qp[i].queueFlags & VK_QUEUE_COMPUTE_BIT) { qfam = i; break; }

    float pri = 1.0f;
    VkDeviceQueueCreateInfo dq = {VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
    dq.queueFamilyIndex = qfam; dq.queueCount = 1; dq.pQueuePriorities = &pri;
    const char *dexts[] = {"VK_KHR_portability_subset"};
    VkDeviceCreateInfo dci = {VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
    dci.queueCreateInfoCount = 1; dci.pQueueCreateInfos = &dq;
    dci.enabledExtensionCount = 1; dci.ppEnabledExtensionNames = dexts;
    VkDevice dev;
    OK(vkCreateDevice(phys, &dci, NULL, &dev));
    VkQueue queue;
    vkGetDeviceQueue(dev, qfam, 0, &queue);

    VkBufferCreateInfo bci = {VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
    bci.size = 4096; bci.usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
    VkBuffer buf;
    OK(vkCreateBuffer(dev, &bci, NULL, &buf));
    VkMemoryRequirements mr;
    vkGetBufferMemoryRequirements(dev, buf, &mr);
    VkPhysicalDeviceMemoryProperties mp;
    vkGetPhysicalDeviceMemoryProperties(phys, &mp);
    uint32_t mt = UINT32_MAX;
    for (uint32_t i = 0; i < mp.memoryTypeCount; i++)
        if ((mr.memoryTypeBits & (1u << i)) && (mp.memoryTypes[i].propertyFlags & (VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) == (VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) { mt = i; break; }
    VkMemoryAllocateInfo mai = {VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    mai.allocationSize = mr.size; mai.memoryTypeIndex = mt;
    VkDeviceMemory mem;
    OK(vkAllocateMemory(dev, &mai, NULL, &mem));
    OK(vkBindBufferMemory(dev, buf, mem, 0));
    volatile uint32_t *p;
    OK(vkMapMemory(dev, mem, 0, 4096, 0, (void **)&p));
    p[0] = 0;

    VkDescriptorSetLayoutBinding b = {0};
    b.binding = 0; b.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER; b.descriptorCount = 1; b.stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
    VkDescriptorSetLayoutCreateInfo dli = {VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
    dli.bindingCount = 1; dli.pBindings = &b;
    VkDescriptorSetLayout dsl;
    OK(vkCreateDescriptorSetLayout(dev, &dli, NULL, &dsl));
    VkPipelineLayoutCreateInfo pli = {VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    pli.setLayoutCount = 1; pli.pSetLayouts = &dsl;
    VkPipelineLayout pl;
    OK(vkCreatePipelineLayout(dev, &pli, NULL, &pl));
    VkShaderModuleCreateInfo smi = {VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO};
    smi.codeSize = hang_spv_len; smi.pCode = (const uint32_t *)hang_spv;
    VkShaderModule sm;
    OK(vkCreateShaderModule(dev, &smi, NULL, &sm));
    VkComputePipelineCreateInfo cpi = {VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO};
    cpi.stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    cpi.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT; cpi.stage.module = sm; cpi.stage.pName = "main";
    cpi.layout = pl;
    VkPipeline pipe;
    OK(vkCreateComputePipelines(dev, VK_NULL_HANDLE, 1, &cpi, NULL, &pipe));

    VkDescriptorPoolSize ps = {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1};
    VkDescriptorPoolCreateInfo dpi = {VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
    dpi.maxSets = 1; dpi.poolSizeCount = 1; dpi.pPoolSizes = &ps;
    VkDescriptorPool dp;
    OK(vkCreateDescriptorPool(dev, &dpi, NULL, &dp));
    VkDescriptorSetAllocateInfo dsai = {VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
    dsai.descriptorPool = dp; dsai.descriptorSetCount = 1; dsai.pSetLayouts = &dsl;
    VkDescriptorSet ds;
    OK(vkAllocateDescriptorSets(dev, &dsai, &ds));
    VkDescriptorBufferInfo dbi = {buf, 0, VK_WHOLE_SIZE};
    VkWriteDescriptorSet w = {VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET};
    w.dstSet = ds; w.dstBinding = 0; w.descriptorCount = 1; w.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER; w.pBufferInfo = &dbi;
    vkUpdateDescriptorSets(dev, 1, &w, 0, NULL);

    VkCommandPoolCreateInfo cpci = {VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    cpci.queueFamilyIndex = qfam;
    VkCommandPool pool;
    OK(vkCreateCommandPool(dev, &cpci, NULL, &pool));
    VkCommandBufferAllocateInfo cai = {VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    cai.commandPool = pool; cai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY; cai.commandBufferCount = 1;
    VkCommandBuffer cb;
    OK(vkAllocateCommandBuffers(dev, &cai, &cb));
    VkCommandBufferBeginInfo bi = {VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    OK(vkBeginCommandBuffer(cb, &bi));
    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pipe);
    vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pl, 0, 1, &ds, 0, NULL);
    vkCmdDispatch(cb, 1, 1, 1);
    OK(vkEndCommandBuffer(cb));

    VkFenceCreateInfo fci = {VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
    VkFence fence;
    OK(vkCreateFence(dev, &fci, NULL, &fence));
    VkSubmitInfo si = {VK_STRUCTURE_TYPE_SUBMIT_INFO};
    si.commandBufferCount = 1; si.pCommandBuffers = &cb;
    double t0 = now_ms();
    OK(vkQueueSubmit(queue, 1, &si, fence));
    printf("submitted the hang at t=0, exit code 70 from MoltenVK is the expected outcome\n"); fflush(stdout);

    for (int i = 0; i < 120; i++) {
        VkResult r = vkWaitForFences(dev, 1, &fence, VK_TRUE, 1000ull * 1000 * 1000);
        printf("t=%.0f ms: wait -> %d, counter %u\n", now_ms() - t0, r, p[0]); fflush(stdout);
        if (r == VK_ERROR_DEVICE_LOST) {
            printf("device lost reached the app, sleeping 5 s to see whether the process survives\n"); fflush(stdout);
            sleep(5);
            printf("STILL ALIVE after the loss, exiting 3\n"); fflush(stdout);
            return 3;
        }
        if (r == VK_SUCCESS) { printf("fence signalled, the gpu was not hung\n"); return 4; }
    }
    printf("no loss reported in 120 s, exiting 5\n");
    return 5;
}
