# Veldmuis ISO Smoke Test

This is the shortest repeatable check for the current Veldmuis ISO and
`archinstall` bootstrap flow.

## 1. Build the local package repo

From the workspace root:

```bash
./scripts/build-local-repo.sh
```

Expected result:

- `repo/repos/veldmuis-core/os/x86_64/veldmuis-core.db.tar.gz` exists
- the current Veldmuis packages are signed and copied into `repo/repos`

## 2. Build the ISO

From the workspace root:

```bash
./scripts/build-archiso.sh
```

Expected result:

- a fresh ISO appears in `build/archiso/out/`
- the profile is built from `repo/archiso/veldmuis`

## 3. Boot a fresh VM from the ISO

Use the newest ISO:

```bash
./scripts/create-arch-test-vm.sh build/archiso/out/veldmuis-YYYY.MM.DD-x86_64.iso
```

Expected result:

- the VM boots into the Veldmuis live session
- the desktop shows Veldmuis branding
- the installer launcher is present on the desktop and in the application menu

## 4. Run the installer

In the VM:

- launch `Install Veldmuis Linux`
- complete the `archinstall` flow
- use a clean virtual disk so old packages do not contaminate the result

Expected result:

- install completes without repo or keyring errors
- reboot lands in the installed Veldmuis system

## 5. Verify the installed system

Run these inside the installed VM:

```bash
pacman -Q veldmuis-release veldmuis-branding veldmuis-desktop
```

Expected result:

- the Veldmuis package stack is installed
- the system boots into Plasma with `sddm`

## Notes

- extra packages currently added by `archinstall` are acceptable for now
- the final installer should own package selection more strictly than the current bootstrap path
