const command = "user.session.abort"

export default {
  id: "ctrl-c-interrupt",
  tui: async (api) => {
    api.keymap.registerLayer({
      mode: "base",
      priority: 10,
      commands: [
        {
          name: command,
          title: "Interrupt current session",
          category: "Session",
          hidden: true,
          enabled: () => {
            const route = api.route.current
            if (route.name !== "session") return false
            const sessionID = route.params?.sessionID
            if (typeof sessionID !== "string") return false
            const status = api.state.session.status(sessionID)
            return status !== undefined && status.type !== "idle"
          },
          run: async () => {
            const route = api.route.current
            if (route.name !== "session") return
            const sessionID = route.params?.sessionID
            if (typeof sessionID !== "string") return
            await api.client.session.abort({ sessionID })
          },
        },
      ],
      bindings: [{ key: "ctrl+c", cmd: command, desc: "Interrupt current session" }],
    })
  },
}
