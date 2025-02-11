# get_bdevs:

```powershell
hostname-3qe8a# ./scripts/rpc.py bdev_get_bdevs
[
  {
    "name": "cache_dev1",
    "aliases": [],
    "product_name": "AIO disk",
    "block_size": 512,
    "num_blocks": 1875382272,
    "uuid": "e7e1c650-a8ba-422b-9be7-b62660a61a1b",
    "assigned_rate_limits": {
      "rw_ios_per_sec": 0,
      "rw_mbytes_per_sec": 0,
      "r_mbytes_per_sec": 0,
      "w_mbytes_per_sec": 0
    },
    "claimed": true,
    "zoned": false,
    "supported_io_types": {
      "read": true,
      "write": true,
      "unmap": false,
      "write_zeroes": true,
      "flush": true,
      "reset": true,
      "nvme_admin": false,
      "nvme_io": false
    },
    "driver_specific": {
      "aio": {
        "filename": "/dev/sde1"
      }
    }
  },
  {
    "name": "core1",
    "aliases": [],
    "product_name": "Ceph Rbd Disk",
    "block_size": 512,
    "num_blocks": 2097152000,
    "uuid": "02dc2eab-27ff-4435-a84c-453600baf641",
    "assigned_rate_limits": {
      "rw_ios_per_sec": 0,
      "rw_mbytes_per_sec": 0,
      "r_mbytes_per_sec": 0,
      "w_mbytes_per_sec": 0
    },
    "claimed": true,
    "zoned": false,
    "supported_io_types": {
      "read": true,
      "write": true,
      "unmap": false,
      "write_zeroes": true,
      "flush": true,
      "reset": true,
      "nvme_admin": false,
      "nvme_io": false
    },
    "driver_specific": {
      "rbd": {
        "pool_name": "vmdisk",
        "rbd_name": "vm01"
      }
    }
  },
  {
    "name": "CAS1",
    "aliases": [],
    "product_name": "SPDK OCF",
    "block_size": 512,
    "num_blocks": 2097152000,
    "uuid": "f54f8d7a-483d-44f5-9ebf-d9a747513903",
    "assigned_rate_limits": {
      "rw_ios_per_sec": 0,
      "rw_mbytes_per_sec": 0,
      "r_mbytes_per_sec": 0,
      "w_mbytes_per_sec": 0
    },
    "claimed": false,
    "zoned": false,
    "supported_io_types": {
      "read": true,
      "write": true,
      "unmap": false,
      "write_zeroes": true,
      "flush": true,
      "reset": false,
      "nvme_admin": false,
      "nvme_io": false
    },
    "driver_specific": {
      "cache_device": "cache_dev1",
      "core_device": "core1",
      "mode": "wt",
      "cache_line_size": 64,
      "metadata_volatile": false
    }
  }
]
hostname-3qe8a#
```