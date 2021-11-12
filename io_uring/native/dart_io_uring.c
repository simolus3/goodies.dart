#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <semaphore.h>
#include <string.h>
#include <sys/eventfd.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <unistd.h>

#include <linux/io_uring.h>

#define CLEAR(x) memset(&x, 0, sizeof(x))
#define RING_BUFFER_SIZE 2048

/* This is x86 specific */
#define read_barrier() __asm__ __volatile__("" ::: "memory")
#define write_barrier() __asm__ __volatile__("" ::: "memory")

struct dart_io_ring_submit {
  unsigned int *head;
  unsigned int *tail;
  unsigned int *ring_mask;
  unsigned int *entry_count;
  unsigned int *flags;
  unsigned int *array;

  struct io_uring_sqe *sqes;
};

struct dart_io_ring_complete {
  unsigned int *head;
  unsigned int *tail;
  unsigned int *ring_mask;
  unsigned int *entry_count;
  struct io_uring_cqe *cqes;
};

struct dart_io_ring {
  int fd;
  struct dart_io_ring_submit submissions;
  struct dart_io_ring_complete completions;
  struct iovec mapped[2];
};

static int io_uring_setup(uint32_t entries, struct io_uring_params *p) {
  return (int)syscall(__NR_io_uring_setup, entries, p);
}

static int io_uring_enter(int ring_fd, unsigned int to_submit,
                          unsigned int min_complete, unsigned int flags) {
  return (int)syscall(__NR_io_uring_enter, ring_fd, to_submit, min_complete,
                      flags, NULL, 0);
}

static int io_uring_register(int ring_fd, unsigned int opcode,
                          void *arg, unsigned int nr_args) {
  return (int)syscall(__NR_io_uring_register, ring_fd, opcode, arg, nr_args);
}

static int return_errno(int inner) {
  if (inner < 0) {
    return -errno;
  } else {
    return inner;
  }
}

struct dart_io_ring* dartio_uring_setup(char **errorOut) {
  struct io_uring_params p;
  CLEAR(p);

  struct dart_io_ring* ring = calloc(1, sizeof(struct dart_io_ring));

  int result = ring->fd = io_uring_setup(RING_BUFFER_SIZE, &p);
  if (result < 0) {
    *errorOut = "Call to io_uring_setup failed!";
    return NULL;
  }

  // Map in information about the submission queue. This mainly includes the
  // indirection array (sq_entries * sizeof(unsigned int)). As the array is
  // located at the end of the structure, we add sq_off.array to also include
  // everything before.
  size_t submissionLength = p.sq_off.array + p.sq_entries * sizeof(unsigned int);
  void *submissionPointer =
      mmap(0, submissionLength,
           PROT_READ | PROT_WRITE, MAP_SHARED | MAP_POPULATE, result,
           IORING_OFF_SQ_RING);
  if (submissionPointer == MAP_FAILED) {
      *errorOut = "Could not map submission data";
      return NULL;
  }
  ring->mapped[0].iov_base = submissionPointer;
  ring->mapped[1].iov_len = submissionLength;

  struct dart_io_ring_submit *submissions = &ring->submissions;
  submissions->head = submissionPointer + p.sq_off.head;
  submissions->tail = submissionPointer + p.sq_off.tail;
  submissions->ring_mask = submissionPointer + p.sq_off.ring_mask;
  submissions->entry_count = submissionPointer + p.sq_off.ring_entries;
  submissions->flags = submissionPointer + p.sq_off.flags;
  submissions->array = submissionPointer + p.sq_off.array;

  // Map in the submission queue entries array
  submissions->sqes = mmap(0, p.sq_entries * sizeof(struct io_uring_sqe),
                           PROT_READ | PROT_WRITE, MAP_SHARED | MAP_POPULATE,
                           result, IORING_OFF_SQES);
  if (submissions->sqes == MAP_FAILED) {
      *errorOut = "Could not map submission SQEs";
      return NULL;
  }

  // Map in the completion queue ring buffer
  size_t completionLength = p.cq_off.cqes + p.cq_entries * sizeof(struct io_uring_cqe);
  void *completionPointer =
      mmap(0, completionLength,
           PROT_READ | PROT_WRITE, MAP_SHARED | MAP_POPULATE, result,
           IORING_OFF_CQ_RING);
  if (completionPointer == MAP_FAILED) {
      *errorOut = "Could not map completion ring";
      return NULL;
  }
  ring->mapped[1].iov_base = completionPointer;
  ring->mapped[1].iov_len = completionLength;

  struct dart_io_ring_complete *completions = &ring->completions;
  completions->head = completionPointer + p.cq_off.head;
  completions->tail = completionPointer + p.cq_off.tail;
  completions->ring_mask = completionPointer + p.cq_off.ring_mask;
  completions->entry_count = completionPointer + p.cq_off.ring_entries;
  completions->cqes = completionPointer + p.cq_off.cqes;

  return ring;
}

void dartio_close(struct dart_io_ring* ring) {
  munmap(ring->mapped[0].iov_base, ring->mapped[0].iov_len);
  munmap(ring->mapped[1].iov_base, ring->mapped[1].iov_len);
  close(ring->fd);
  free(ring);
}

int dartio_socket(int domain, int type, int protocol) {
  return return_errno(socket(domain, type, protocol));
}

int dartio_bind(int sockfd, const struct sockaddr *addr, uint32_t addlen) {
  return return_errno(bind(sockfd, addr, addlen));
}

int dartio_getsockname(int sockfd, struct sockaddr *restrict addr, uint32_t *restrict addrlen) {
  return return_errno(getsockname(sockfd, addr, addrlen));
}

int dartio_getpeername(int sockfd, struct sockaddr *restrict addr, uint32_t *restrict addrlen) {
  return return_errno(getpeername(sockfd, addr, addrlen));
}

int dartio_getsockopt(int sockfd, int level, int optname, void *restrict optval, uint32_t *restrict optlen) {
  return return_errno(getsockopt(sockfd, level, optname, optval, optlen));
}

int dartio_setsockopt(int sockfd, int level, int optname, const void *optval, uint32_t optlen) {
  return return_errno(setsockopt(sockfd, level, optname, optval, optlen));
}

int dartio_listen(int sockfd, int backlog) {
  return return_errno(listen(sockfd, backlog));
}

long int dartio_lseek(int fd, long int offset, int whence) {
  return return_errno(lseek(fd, offset, whence));
}

int dartio_ftruncate(int fd, long int length) {
  return return_errno(ftruncate(fd, length));
}

int dartio_uring_enter(int fd, unsigned int submitted, unsigned int min_complete, unsigned int flags) {
  return io_uring_enter(fd, submitted, min_complete, flags);
}

int dartio_uring_register(struct dart_io_ring* ring, unsigned int opcode, void *arg, unsigned int nr_args) {
  int result = io_uring_register(ring->fd, opcode, arg, nr_args);
  if (result) {
    return -errno;
  } else {
    return 0;
  }
}
