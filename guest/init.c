// SPDX-License-Identifier: MIT
// Minimal PID 1 for the AArch64 NSM request-dump POC.
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/reboot.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

#define NSM_MAGIC 0x0A
#define NSM_RESPONSE_MAX_SIZE 0x3000

struct nsm_iovec {
    uint64_t addr;
    uint64_t len;
};

struct nsm_raw {
    struct nsm_iovec request;
    struct nsm_iovec response;
};

#define NSM_IOCTL_RAW _IOWR(NSM_MAGIC, 0x0, struct nsm_raw)

static const unsigned char describe_nsm[] = {
    0xa1, 0x6b, 'D', 'e', 's', 'c', 'r', 'i', 'b', 'e', 'N', 'S', 'M', 0xa0,
};
static const unsigned char attestation[] = {
    0xa1, 0x6b, 'A', 't', 't', 'e', 's', 't', 'a', 't', 'i', 'o', 'n',
    0xa1, 0x65, 'n', 'o', 'n', 'c', 'e', 0x49,
    'p', 'o', 'c', '-', 'n', 'o', 'n', 'c', 'e',
};

static void log_errno(const char *what)
{
    fprintf(stderr, "%s: %s\n", what, strerror(errno));
}

static int load_module(const char *path)
{
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    struct stat st;
    void *module;
    int rc;

    if (fd < 0 || fstat(fd, &st) < 0) {
        log_errno("open/fstat nsm.ko");
        if (fd >= 0) {
            close(fd);
        }
        return -1;
    }
    module = mmap(NULL, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (module == MAP_FAILED) {
        log_errno("mmap nsm.ko");
        return -1;
    }
    rc = syscall(SYS_init_module, module, st.st_size, "");
    munmap(module, st.st_size);
    if (rc != 0 && errno != EEXIST) {
        log_errno("init_module nsm.ko");
        return -1;
    }
    return 0;
}

static int send_request(int fd, const char *name, const unsigned char *request,
                        size_t request_len)
{
    unsigned char response[NSM_RESPONSE_MAX_SIZE];
    struct nsm_raw raw = {
        .request = {.addr = (uint64_t)(uintptr_t)request, .len = request_len},
        .response = {.addr = (uint64_t)(uintptr_t)response, .len = sizeof(response)},
    };

    if (ioctl(fd, NSM_IOCTL_RAW, &raw) != 0) {
        log_errno(name);
        return -1;
    }
    printf("%s response received (%llu bytes)\n", name,
           (unsigned long long)raw.response.len);
    return 0;
}

static void wait_for_nsm(void)
{
    struct timespec pause = {.tv_sec = 0, .tv_nsec = 100000000L};
    for (int i = 0; i < 100; ++i) {
        if (access("/dev/nsm", F_OK) == 0) {
            return;
        }
        nanosleep(&pause, NULL);
    }
}

int main(void)
{
    int fd;

    mount("proc", "/proc", "proc", 0, NULL);
    mount("sysfs", "/sys", "sysfs", 0, NULL);
    mount("devtmpfs", "/dev", "devtmpfs", 0, NULL);
    puts("hello from enclave");

    if (load_module("/nsm.ko") != 0) {
        goto out;
    }
    puts("waiting for /dev/nsm");
    wait_for_nsm();
    fd = open("/dev/nsm", O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        log_errno("open /dev/nsm");
        goto out;
    }
    puts("/dev/nsm available");
    send_request(fd, "DescribeNSM", describe_nsm, sizeof(describe_nsm));
    send_request(fd, "Attestation", attestation, sizeof(attestation));
    close(fd);

out:
    sync();
    reboot(LINUX_REBOOT_CMD_POWER_OFF);
    for (;;) {
        pause();
    }
}
