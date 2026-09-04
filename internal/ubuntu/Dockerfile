FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq \
 && apt-get install -y -qq \
      qemu-user-static binfmt-support \
      e2fsprogs fdisk gdisk dosfstools rsync \
      ca-certificates openssh-client \
 && rm -rf /var/lib/apt/lists/*

COPY scripts/mkimage.sh /usr/local/bin/cyta-mkimage
RUN chmod +x /usr/local/bin/cyta-mkimage

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/cyta-mkimage"]
