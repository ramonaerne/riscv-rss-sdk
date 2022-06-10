#include <stdio.h>
#include <stdint.h>
#include <sys/mman.h>
#include <sys/stat.h>        /* For mode constants */
#include <fcntl.h>           /* For O_* constants */

#include <sys/types.h>
#include <unistd.h>

#define SPM_SIZE 0x1000

#define BANNER \
    "**************************************\n" \
    " Test mmio into spike via posix shm   \n" \
    "**************************************\n" \
    " This simulates a 4k mmio region accessible from host \n" \
    " run `make spike-plugin` in another process \n" \
    " which will run the spike-simulater until a nonzero 32bit is read\n" \
    " starting from shm address 0 (which is mapped to 0x0x10000000 in spike)\n" \
    " and then print out the number of 32bit values read at that base address\n"

int main() {
    mode_t oldumask;
    char *name;
    uint8_t *ptr;
    int fd;
    struct stat statbuf;

    printf("%s", BANNER);

    oldumask = umask(0);
    name   = "/triton.spm";
    fd = shm_open(name, O_CREAT | O_RDWR, 0644);
    umask(oldumask);

    if(!fd) {
        printf("failed to open shm\n");
        return -1;
    }

    fstat(fd, &statbuf);
    if (statbuf.st_size != SPM_SIZE) {
        if (ftruncate(fd, SPM_SIZE)) {
            printf("failed to resize shm\n");
            shm_unlink(name);
        }
        fstat(fd, &statbuf);
    }

    ptr = (u_char *) mmap(NULL, statbuf.st_size, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
    printf("Shared Mem Address: %p [0..%lu]\n", ptr, statbuf.st_size-1);

    int addr, val;
    do {
        printf("write to mem in the format addr=X, addr=-1 exits\n");
        fscanf(stdin, "%d=%d", &addr, &val);
        if (addr >= 0 && addr < SPM_SIZE) {
            *(((uint32_t *)ptr) + addr) = val;
        }
    } while(addr >= 0);

    munmap(ptr, statbuf.st_size);
    shm_unlink(name);
    return 0;
}