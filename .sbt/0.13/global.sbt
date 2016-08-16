addCommandAlias("off", "set offline := true")
addCommandAlias("re", "reload")
addCommandAlias("c", "compile")
addCommandAlias("cc", "~compile")
addCommandAlias("ccc", ";clean;~compile")
addCommandAlias("r", "run")
addCommandAlias("cr", ";clean; run")
addCommandAlias("rr", "~run")
addCommandAlias("t", "test")
addCommandAlias("tt", "~test")
addCommandAlias("pl", ";set isSnapshot := true;publish-local")
addCommandAlias("ppl", "publish-local")
addCommandAlias("du", "dependencyUpdates")
addCommandAlias("coverageAll", ";clean ;coverage ;test ;coverageReport")
addCommandAlias("opt", """set scalacOptions ++= Seq("-Xdisable-assertions", "-optimize", "-Yinline")""")

maxErrors := 3

// net.virtualvoid.sbt.graph.Plugin.graphSettings
