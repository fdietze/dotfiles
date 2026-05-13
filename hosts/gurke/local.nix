{
  disks = {
    luksRoot = "/dev/disk/by-uuid/81409765-5560-4b29-8f5c-235f27b58f85";
    root = "/dev/disk/by-uuid/bcfc9aca-bb80-4af1-8541-ae34fd5c6f06";
    boot = "/dev/disk/by-uuid/CBB0-3A80";
    swap = "/dev/disk/by-uuid/31593de0-1b27-46f7-8a2a-3d83cead21bf";
    silo = "UUID=2b199ae4-5884-415f-a717-7df4d666f6bc";
  };

  devices = {
    garminHeartRateAddress = "F0:99:19:32:80:03";
  };
}
