// enable repl colors
initialize ~= (_ => if (ConsoleLogger.formatEnabled) sys.props("scala.color") = "true")
triggeredMessage in ThisBuild := Watched.clearWhenTriggered

reporterConfig := reporterConfig.value.withReverseOrder(true)
clippyColorsEnabled := true
