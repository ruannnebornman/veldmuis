if status is-interactive
    if test -r /proc/sys/kernel/osrelease; and string match -q -i '*microsoft*' -- (command cat /proc/sys/kernel/osrelease)
        /usr/lib/veldmuis/veldmuis-user-defaults-update --seed >/dev/null 2>&1 &
        disown
    end
end
