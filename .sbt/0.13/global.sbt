// enable repl colors
initialize ~= (_ => if (ConsoleLogger.formatEnabled) sys.props("scala.color") = "true")

triggeredMessage in ThisBuild := Watched.clearWhenTriggered

import sbt.errorssummary.Plugin.autoImport._
reporterConfig := reporterConfig.value.withReverseOrder(true)

import com.softwaremill.clippy.ClippySbtPlugin._
clippyColorsEnabled := true
