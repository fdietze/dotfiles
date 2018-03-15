addCommandAlias("off", "set offline := true")
addCommandAlias("on", "set offline := false")
addCommandAlias("re", "reload")
addCommandAlias("rec", ";reload; compile")
addCommandAlias("recc", ";reload; ~compile")
addCommandAlias("ret", ";reload; test")
addCommandAlias("up", "update")
addCommandAlias("c", "compile")
addCommandAlias("cl", "clean")
addCommandAlias("tc", "test:compile")
addCommandAlias("tcc", "~test:compile")
addCommandAlias("cc", "~compile")
addCommandAlias("ccc", ";clean;~compile")
addCommandAlias("r", "run")
addCommandAlias("cr", ";clean; run")
addCommandAlias("rr", "~run")
addCommandAlias("t", "test")
addCommandAlias("tt", "~test")
addCommandAlias("pl", ";set isSnapshot := true;publishLocal")
addCommandAlias("ppl", "publish-local")
addCommandAlias("cd", "project")
addCommandAlias("cdg", "project root")
addCommandAlias("l", "projects")
addCommandAlias("cn", "console")
addCommandAlias("s211", "++2.11.12")

addCommandAlias("du", "dependencyUpdates")
addCommandAlias("coverageAll", ";clean ;coverage ;test ;coverageReport")
addCommandAlias("opt", """set scalacOptions ++= Seq("-Xdisable-assertions", "-optimize", "-Yinline")""")

maxErrors := 4

// ctrl+c does not quit
// cancelable in Global := true

// enable repl colors
initialize ~= (_ => if (ConsoleLogger.formatEnabled) sys.props("scala.color") = "true")

triggeredMessage in ThisBuild := Watched.clearWhenTriggered

