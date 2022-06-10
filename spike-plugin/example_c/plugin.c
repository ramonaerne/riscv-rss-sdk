#include <riscv/mmio_plugin.h>
#include <stdio.h>
#include <string.h>

#include <stdio.h>
#include <sys/mman.h>
#include <sys/stat.h>        /* For mode constants */
#include <fcntl.h>           /* For O_* constants */

#include <sys/types.h>
#include <unistd.h>

#define SPM_SIZE 100
static const char *shm_name = "/triton.spm";

void* test_mmio_plugin_alloc(const char* args)
{
    printf("ALLOC -- ARGS=%s\n", args);

    mode_t oldumask = umask(0);
    // TODO: name the shm according to the args input
    int fd = shm_open(shm_name, O_CREAT | O_RDWR, 0644);
    umask(oldumask);

    if(!fd) {
        printf("failed to open shm\n");
        return NULL;
    }

    struct stat statbuf;
    fstat(fd, &statbuf);

    printf("len of shm is: %lu\n", statbuf.st_size);

    if (statbuf.st_size != SPM_SIZE) {
        if (ftruncate(fd, SPM_SIZE)) {
            printf("failed to resize shm\n");
            shm_unlink(shm_name);
        }
        fstat(fd, &statbuf);
    }

    u_char *buf = (u_char *) mmap(NULL, statbuf.st_size, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
    printf("Shared Mem Address: %p [0..%lu]\n", buf, statbuf.st_size-1);
    return (void*)buf;
}

bool test_mmio_plugin_load(void* self, reg_t addr, size_t len, uint8_t* bytes)
{
    printf("LOAD -- SELF=%p ADDR=0x%lx LEN=%lu BYTES=%p\n", self, addr, len, (void*)bytes);
    memcpy(bytes, self + addr, len);
    switch(len) {
    case 4:
        printf("%x\n", *((uint32_t *)bytes));
        break;
    case 8:
        printf("%lx\n", *((uint64_t *)bytes));
        break;
    }

    return true;
}

bool test_mmio_plugin_store(void* self, reg_t addr, size_t len, const uint8_t* bytes)
{
    printf("STORE -- SELF=%p ADDR=0x%lx LEN=%lu BYTES=%p\n", self, addr, len, (const void*)bytes);
    
    memcpy(self + addr, bytes, len);
    switch(len) {
    case 4:
        printf("%x\n", *((uint32_t *)bytes));
        break;
    case 8:
        printf("%lx\n", *((uint64_t *)bytes));
        break;
    }
    return true;
}

void test_mmio_plugin_dealloc(void* self)
{
    printf("DEALLOC -- SELF=%p\n", self);
    
    munmap(self, SPM_SIZE);
    shm_unlink(shm_name);
}

__attribute__((constructor)) static void on_load()
{
  static mmio_plugin_t test_mmio_plugin = {
      test_mmio_plugin_alloc,
      test_mmio_plugin_load,
      test_mmio_plugin_store,
      test_mmio_plugin_dealloc
  };

  register_mmio_plugin("test_mmio_plugin", &test_mmio_plugin);
}
