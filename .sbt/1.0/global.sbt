// enable repl colors
initialize ~= (_ => if (ConsoleLogger.formatEnabled) sys.props("scala.color") = "true")
triggeredMessage in ThisBuild := Watched.clearWhenTriggered

shellPrompt := { state =>
  "%s> ".format(Project.extract(state).currentProject.id)
}

reporterConfig := reporterConfig.value.withReverseOrder(true)
