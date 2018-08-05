/* maxErrors := 4 */

// ctrl+c does not quit
// cancelable in Global := true

// enable repl colors
initialize ~= (_ => if (ConsoleLogger.formatEnabled) sys.props("scala.color") = "true")

triggeredMessage in ThisBuild := Watched.clearWhenTriggered

reporterConfig := reporterConfig.value.withReverseOrder(true)

clippyColorsEnabled := true
