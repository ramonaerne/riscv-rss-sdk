# RISCV should either be unset, or set to point to a directory that contains
# a toolchain install tree that was built via other means.
RISCV ?= $(CURDIR)/toolchain
PATH := $(RISCV)/bin:$(PATH)
ISA ?= rv64imafdc
ABI ?= lp64d
# choose opensbi or bbl here
BL ?= opensbi

topdir := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
topdir := $(topdir:/=)
srcdir := $(topdir)/repo
confdir := $(topdir)/conf
wrkdir := $(CURDIR)/build

toolchain_srcdir := $(srcdir)/riscv-gnu-toolchain
toolchain_wrkdir := $(wrkdir)/riscv-gnu-toolchain
toolchain_dest := $(CURDIR)/toolchain

buildroot_srcdir := $(srcdir)/buildroot
buildroot_initramfs_wrkdir := $(wrkdir)/buildroot_initramfs
buildroot_initramfs_tar := $(buildroot_initramfs_wrkdir)/images/rootfs.tar
buildroot_initramfs_config := $(confdir)/buildroot_initramfs_config
buildroot_initramfs_sysroot_stamp := $(wrkdir)/.buildroot_initramfs_sysroot
buildroot_initramfs_sysroot := $(wrkdir)/buildroot_initramfs_sysroot

busybox_srcdir := $(srcdir)/busybox
busybox_wrkdir := $(wrkdir)/busybox
busybox := $(busybox_wrkdir)/_install
busybox_initramfs_dir := $(wrkdir)/initramfs
busybox_initramfs := $(wrkdir)/initramfs.cpio.gz
initscript := $(confdir)/init
busybox_defconfig := $(confdir)/busybox_defconfig

linux_srcdir := $(srcdir)/linux
linux_wrkdir := $(wrkdir)/linux
linux_defconfig := $(confdir)/linux_defconfig

vmlinux := $(linux_wrkdir)/vmlinux
vmlinux_stripped := $(linux_wrkdir)/vmlinux-stripped
linux_image := $(linux_wrkdir)/arch/riscv/boot/Image

pk_srcdir := $(srcdir)/riscv-pk
pk_wrkdir := $(wrkdir)/riscv-pk
bbl := $(pk_wrkdir)/bbl
pk  := $(pk_wrkdir)/pk

opensbi_srcdir := $(srcdir)/opensbi
opensbi_wrkdir := $(wrkdir)/opensbi
fw_jump := $(opensbi_wrkdir)/platform/generic/firmware/fw_jump.elf

spike_srcdir := $(srcdir)/riscv-isa-sim
spike_wrkdir := $(wrkdir)/riscv-isa-sim
spike := $(toolchain_dest)/bin/spike

qemu_srcdir := $(srcdir)/qemu
qemu_wrkdir := $(wrkdir)/qemu
qemu :=  $(toolchain_dest)/bin/qemu-system-riscv64

target_linux  := riscv64-unknown-linux-gnu
target_newlib := riscv64-unknown-elf

.PHONY: all
all: sim
build: $(fw_jump) $(qemu) $(spike)

newlib: $(RISCV)/bin/$(target_newlib)-gcc


ifneq ($(RISCV),$(toolchain_dest))
$(RISCV)/bin/$(target_linux)-gcc:
	$(error The RISCV environment variable was set, but is not pointing at a toolchain install tree)
endif

$(toolchain_dest)/bin/$(target_linux)-gcc: $(toolchain_srcdir)
	mkdir -p $(toolchain_wrkdir)
	$(MAKE) -C $(linux_srcdir) O=$(toolchain_wrkdir) ARCH=riscv INSTALL_HDR_PATH=$(abspath $(toolchain_srcdir)/linux-headers) headers_install
	cd $(toolchain_wrkdir); $(toolchain_srcdir)/configure \
		--prefix=$(toolchain_dest) \
		--with-arch=$(ISA) \
		--with-abi=$(ABI) 
	$(MAKE) -C $(toolchain_wrkdir) linux
	# sed 's/^#define LINUX_VERSION_CODE.*/#define LINUX_VERSION_CODE 329226/' -i $(toolchain_dest)/sysroot/usr/include/linux/version.h

toolchain: $(toolchain_dest)/bin/$(target_linux)-gcc

$(toolchain_dest)/bin/$(target_newlib)-gcc: $(toolchain_srcdir)
	mkdir -p $(toolchain_wrkdir)
	cd $(toolchain_wrkdir); $(toolchain_srcdir)/configure \
		--prefix=$(toolchain_dest) \
		--enable-multilib
	$(MAKE) -C $(toolchain_wrkdir) 

$(buildroot_initramfs_wrkdir)/.config: $(buildroot_srcdir)
	rm -rf $(dir $@)
	mkdir -p $(dir $@)
	cp $(buildroot_initramfs_config) $@
	$(MAKE) -C $< RISCV=$(RISCV) PATH="$(PATH)" O=$(buildroot_initramfs_wrkdir) olddefconfig CROSS_COMPILE=riscv64-unknown-linux-gnu-

$(buildroot_initramfs_tar): $(buildroot_srcdir) $(buildroot_initramfs_wrkdir)/.config $(RISCV)/bin/$(target_linux)-gcc $(buildroot_initramfs_config)
	$(MAKE) -C $< RISCV=$(RISCV) PATH="$(PATH)" O=$(buildroot_initramfs_wrkdir) -j$(nproc)

.PHONY: buildroot_initramfs-menuconfig
buildroot_initramfs-menuconfig: $(buildroot_initramfs_wrkdir)/.config $(buildroot_srcdir)
	$(MAKE) -C $(dir $<) O=$(buildroot_initramfs_wrkdir) menuconfig
	$(MAKE) -C $(dir $<) O=$(buildroot_initramfs_wrkdir) savedefconfig
	cp $(dir $<)/defconfig conf/buildroot_initramfs_config

$(buildroot_initramfs_sysroot): $(buildroot_initramfs_tar)
	mkdir -p $(buildroot_initramfs_sysroot)
	tar -xpf $< -C $(buildroot_initramfs_sysroot) --exclude ./dev --exclude ./usr/share/locale

$(linux_wrkdir)/.config: $(linux_defconfig) $(linux_srcdir) toolchain
	mkdir -p $(dir $@)
	cp -p $< $@
	$(MAKE) -C $(linux_srcdir) O=$(linux_wrkdir) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- olddefconfig
	echo $(ISA)
	echo $(filter rv32%,$(ISA))
ifeq (,$(filter rv%c,$(ISA)))
	sed 's/^.*CONFIG_RISCV_ISA_C.*$$/CONFIG_RISCV_ISA_C=n/' -i $@
	$(MAKE) -C $(linux_srcdir) O=$(linux_wrkdir) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- olddefconfig
endif
ifeq ($(ISA),$(filter rv32%,$(ISA)))
	sed 's/^.*CONFIG_ARCH_RV32I.*$$/CONFIG_ARCH_RV32I=y/' -i $@
	sed 's/^.*CONFIG_ARCH_RV64I.*$$/CONFIG_ARCH_RV64I=n/' -i $@
	$(MAKE) -C $(linux_srcdir) O=$(linux_wrkdir) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- olddefconfig
endif

# $(vmlinux): $(linux_srcdir) $(linux_wrkdir)/.config $(buildroot_initramfs_sysroot) 
# 	$(MAKE) -C $< O=$(linux_wrkdir) \
# 		CONFIG_INITRAMFS_SOURCE="$(confdir)/initramfs.txt $(buildroot_initramfs_sysroot)" \
# 		CONFIG_INITRAMFS_ROOT_UID=$(shell id -u) \
# 		CONFIG_INITRAMFS_ROOT_GID=$(shell id -g) \
# 		CROSS_COMPILE=riscv64-unknown-linux-gnu- \
# 		ARCH=riscv \
# 		KBUILD_CFLAGS_KERNEL="-save-temps=obj" \
# 		all -j$(nproc)

$(vmlinux): $(linux_srcdir) $(linux_wrkdir)/.config
	$(MAKE) -C $< O=$(linux_wrkdir) \
		CROSS_COMPILE=riscv64-unknown-linux-gnu- \
		ARCH=riscv \
		KBUILD_CFLAGS_KERNEL="-save-temps=obj" \
		all -j$(nproc)

$(vmlinux_stripped): $(vmlinux)
	$(target_linux)-strip -o $@ $<

$(linux_image): $(vmlinux)

.PHONY: linux-menuconfig
linux-menuconfig: $(linux_wrkdir)/.config
	$(MAKE) -C $(linux_srcdir) O=$(dir $<) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- menuconfig
	$(MAKE) -C $(linux_srcdir) O=$(dir $<) ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- savedefconfig
	# cp $(dir $<)/defconfig conf/linux_defconfig

$(bbl): $(pk_srcdir) $(vmlinux_stripped)
	rm -rf $(pk_wrkdir)
	mkdir -p $(pk_wrkdir)
	cd $(pk_wrkdir) && $</configure \
		--host=$(target_linux) \
		--with-payload=$(vmlinux_stripped) \
		--enable-logo \
		--with-logo=$(abspath conf/logo.txt) \
		--with-dts=$(abspath conf/spike.dts)
	CFLAGS="-mabi=$(ABI) -march=$(ISA)" $(MAKE) -C $(pk_wrkdir)


$(pk): $(pk_srcdir) $(RISCV)/bin/$(target_newlib)-gcc
	rm -rf $(pk_wrkdir)
	mkdir -p $(pk_wrkdir)
	cd $(pk_wrkdir) && $</configure \
		--host=$(target_newlib) \
		--prefix=$(abspath $(toolchain_dest))
	CFLAGS="-mabi=$(ABI) -march=$(ISA)" $(MAKE) -C $(pk_wrkdir)
	$(MAKE) -C $(pk_wrkdir) install

$(fw_jump): $(opensbi_srcdir) $(linux_image) $(RISCV)/bin/$(target_linux)-gcc
	rm -rf $(opensbi_wrkdir)
	mkdir -p $(opensbi_wrkdir)
	$(MAKE) -C $(opensbi_srcdir) FW_PAYLOAD_PATH=$(linux_image) PLATFORM=generic O=$(opensbi_wrkdir) CROSS_COMPILE=riscv64-unknown-linux-gnu-

# $(busybox_wrkdir)/.config: $(busybox_defconfig) $(busybox_srcdir) $(RISCV)/bin/$(target_linux)-gcc
$(busybox_wrkdir)/.config: $(busybox_defconfig) $(busybox_srcdir)
	mkdir -p $(busybox_wrkdir)
	cp -p $< $@
	make -C $(busybox_srcdir) O=$(busybox_wrkdir) oldconfig

$(busybox): $(busybox_srcdir) $(busybox_wrkdir)/.config $(RISCV)/bin/$(target_linux)-gcc
	make -C $(busybox_srcdir) O=$(busybox_wrkdir) -j$(nproc)
	make -C $(busybox_srcdir) O=$(busybox_wrkdir) install

$(busybox_initramfs): $(busybox) $(initscript)
	[ -d $(busybox_initramfs_dir) ] && rm -r $(busybox_initramfs_dir)
	mkdir -p $(busybox_initramfs_dir)
	cd $(busybox_initramfs_dir) && mkdir -p bin sbin etc proc sys usr/bin usr/sbin
	cp -a $(busybox)/* $(busybox_initramfs_dir)
	cp $(initscript) $(busybox_initramfs_dir)/init
	cp $(wrkdir)/../linux-bin-test/hello_world $(busybox_initramfs_dir)/bin/
	# cp $(confdir)/initramfs.txt $(busybox_initramfs_dir)/init
	# cp -a $(buildroot_initramfs_sysroot)/* $(busybox_initramfs_dir)
	chmod +x $(busybox_initramfs_dir)/init
	cd $(busybox_initramfs_dir) && find . -print0 | cpio --null -ov --format=newc | gzip -9 > $@

busybox-initramfs: $(busybox_initramfs)

$(spike): $(spike_srcdir) 
	rm -rf $(spike_wrkdir)
	mkdir -p $(spike_wrkdir)
	mkdir -p $(dir $@)
	cd $(spike_wrkdir) && $</configure \
		--prefix=$(dir $(abspath $(dir $@))) 
	$(MAKE) -C $(spike_wrkdir) -j$(nproc)
	$(MAKE) -C $(spike_wrkdir) install
	touch -c $@

$(qemu): $(qemu_srcdir)
	rm -rf $(qemu_wrkdir)
	mkdir -p $(qemu_wrkdir)
	mkdir -p $(dir $@)
	cd $(qemu_wrkdir) && $</configure \
		--disable-docs \
		--disable-tests \
		--prefix=$(dir $(abspath $(dir $@))) \
		--target-list=riscv64-linux-user,riscv64-softmmu
	$(MAKE) -C $(qemu_wrkdir) -j$(nproc)
	$(MAKE) -C $(qemu_wrkdir) install
	touch -c $@

.PHONY: buildroot_initramfs_sysroot vmlinux bbl fw_jump busybox
buildroot_initramfs_sysroot: $(buildroot_initramfs_sysroot)
vmlinux: $(vmlinux)
bbl: $(bbl)
fw_image: $(fw_jump)
busybox: $(busybox)

.PHONY: clean
clean:
	rm -rf -- $(wrkdir) $(toolchain_dest)

ifeq ($(BL),opensbi)
.PHONY: sim
sim: $(fw_jump) $(spike)
	$(spike) --isa=$(ISA) -p4 --kernel $(linux_image) $(fw_jump)
.PHONY: qemu
qemu: $(qemu) $(fw_jump) $(busybox_initramfs)
	$(qemu) -d guest_errors -nographic -machine virt -m 256M -bios $(fw_jump) -kernel $(linux_image) \
	-initrd $(busybox_initramfs) -append "console=ttyS0"
else ifeq ($(BL),bbl)
.PHONY: sim
sim: $(bbl) $(spike)
	$(spike) --isa=$(ISA) -p4 $(bbl)
endif

.PHONY: qemu-spike
qemu-spike: $(qemu)
	$(qemu) -nographic -machine spike -m 256M -bios $(fw_jump) -kernel $(linux_image) \
	-append "root=/dev/ram rw console=hvc0 earlycon=sbi"

./spike-plugin/host-devmem/host-devmem: ./spike-plugin/host-devmem/host_devmem.c
	make -C spike-plugin/host-devmem

host-devmem: ./spike-plugin/host-devmem/host-devmem
	./spike-plugin/host-devmem/host-devmem

spike-plugin/example_c/plugin.so:
	make -C spike-plugin/example_c

spike-plugin/plugin_test/plugin_test:
	make -C spike-plugin/plugin_test

spike-plugin: spike-plugin/example_c/plugin.so spike-plugin/plugin_test/plugin_test
	$(spike) -m1 --extlib=spike-plugin/example_c/plugin.so --device=test_mmio_plugin,0x10000000,argument spike-plugin/plugin_test/plugin_test
