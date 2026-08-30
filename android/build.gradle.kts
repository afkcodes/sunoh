allprojects {
    repositories {
        google()
        mavenCentral()
        // JitPack — serves MetrolistGroup/innertubex, the InnerTube
        // extraction library behind the YouTube Music tier. Not on Maven
        // Central; built from the GitHub tag by JitPack on first request.
        maven { url = uri("https://jitpack.io") }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
