/*
 * Jailhouse, a Linux-based partitioning hypervisor
 *
 * Configuration for APU baremetal demo inmate on Xilinx ZynqMP ZCU104:
 * 1 CPU (APU core 3), 32M RAM, UART1
 *
 * Copyright (c) Universita' di Napoli Federico II, 2026
 *
 * This work is licensed under the terms of the GNU GPL, version 2.  See
 * the COPYING file in the top-level directory.
 *
 * Modelled on zynqmp-kv260-APU-inmate-demo.c. Deliberately has no ivshmem
 * device: the legacy zynqmp-zcu104-inmate-demo.c declares one with
 * .shmem_dev_id = 0 and .bdf = 1 << 3, which collide with the root cell's
 * first ivshmem endpoint, so `cell create` fails in ivshmem.c with -EBUSY.
 *
 * Memory placement: CPU 3 is held out of the Linux scheduler by
 * "isolcpus=domain,managed_irq,2-3" in boot_jailhouse.cmd, and the RAM/SHM
 * below live inside the rproc@3ad00000 reservation of system_jailhouse.dts
 * (0x3ad00000..0x3ecfffff, 64M, no-map), so Linux never maps these pages.
 * The rproc@3ed00000 block is left alone: the Omnivisor root cell uses
 * 0x3ed00000 and 0x3ed40000 for RPU firmware.
 */

#include <jailhouse/types.h>
#include <jailhouse/cell-config.h>

struct {
	struct jailhouse_cell_desc cell;
	__u64 cpus[1];
	struct jailhouse_memory mem_regions[5];
	struct jailhouse_irqchip irqchips[1];
} __attribute__((packed)) config = {
	.cell = {
		.signature = JAILHOUSE_CELL_DESC_SIGNATURE,
		.revision = JAILHOUSE_CONFIG_REVISION,
		.architecture = JAILHOUSE_ARM64,
		.name = "inmate-demo-APU",
		.flags = JAILHOUSE_CELL_PASSIVE_COMMREG,

		.cpu_set_size = sizeof(config.cpus),
		.num_memory_regions = ARRAY_SIZE(config.mem_regions),
		.num_irqchips = ARRAY_SIZE(config.irqchips),
		.num_pci_devices = 0,

		.console = {
			.address = 0xff010000,
			.type = JAILHOUSE_CON_TYPE_XUARTPS,
			.flags = JAILHOUSE_CON_ACCESS_MMIO |
				 JAILHOUSE_CON_REGDIST_4,
		},
	},

	.cpus = {
		0x8,
	},

	.mem_regions = {
		/* UART1 */ {
			.phys_start = 0xff010000,
			.virt_start = 0xff010000,
			.size = 0x1000,
			.flags = JAILHOUSE_MEM_READ | JAILHOUSE_MEM_WRITE |
				JAILHOUSE_MEM_IO | JAILHOUSE_MEM_ROOTSHARED,
		},
		/* SYSTEM COUNTER */ {
			.phys_start = 0xff250000,
			.virt_start = 0xff250000,
			.size = 0x1000,
			.flags = JAILHOUSE_MEM_READ | JAILHOUSE_MEM_WRITE |
				JAILHOUSE_MEM_IO | JAILHOUSE_MEM_ROOTSHARED,
		},
		/* SHM */ {
			.phys_start = 0x3ad00000,
			.virt_start = 0x3ad00000,
			.size = 0x10000,
			.flags = JAILHOUSE_MEM_READ | JAILHOUSE_MEM_WRITE |
				JAILHOUSE_MEM_IO | JAILHOUSE_MEM_ROOTSHARED,
		},
		/* RAM */ {
			.phys_start = 0x3ae00000,
			.virt_start = 0,
			.size = 0x2000000,
			.flags = JAILHOUSE_MEM_READ | JAILHOUSE_MEM_WRITE |
				JAILHOUSE_MEM_EXECUTE | JAILHOUSE_MEM_LOADABLE,
		},
		/* communication region */ {
			.virt_start = 0x80000000,
			.size = 0x00001000,
			.flags = JAILHOUSE_MEM_READ | JAILHOUSE_MEM_WRITE |
				JAILHOUSE_MEM_COMM_REGION,
		},
	},

	.irqchips = {
		/* GIC */ {
			.address = 0xf9010000,
			.pin_base = 32,
			.pin_bitmap = {
				0, 0, 0, 0
			},
		},
	},
};
