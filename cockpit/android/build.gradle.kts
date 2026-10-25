allprojects {
    repositories {
        google()
        mavenCentral()
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
// Alguns plugins (ex.: desktop_drop, desktop-only) fixam compileSdk 33, mas suas
// deps transitivas (exifinterface) exigem 34+. Forcamos 36 em todo modulo Android
// de plugin. Registrado ANTES do evaluationDependsOn abaixo (afterEvaluate nao pode
// ser registrado apos a avaliacao). Esses plugins desktop serao gateados pra fora
// do mobile depois; por ora isso destrava o build. Ver plan/59 (Wave 2).
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            // AGP 9 removeu a BaseExtension legada; a DSL nova é CommonExtension.
            (ext as com.android.build.api.dsl.CommonExtension).compileSdk = 36
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
