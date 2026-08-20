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

    // 修复 Windows + AGP 8.x 上 extractReleaseAnnotations / extractDebugAnnotations 任务
    // AccessDeniedException bug（AndroidLintWorkAction 在 Windows 上写 annotations.zip 时报拒绝访问）
    // 解决：禁用任务，但在配置阶段预创建空 typedefs.txt 文件，让下游 syncReleaseLibJars 能找到输入
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt is com.android.build.gradle.LibraryExtension) {
            // 为 release 和 debug variant 预创建空的 typedefs.txt
            listOf("release", "debug").forEach { variant ->
                val typedefsFile = layout.buildDirectory.file(
                    "intermediates/annotations_typedef_file/$variant/extract${variant.replaceFirstChar { it.uppercase() }}Annotations/typedefs.txt"
                ).get().asFile
                if (!typedefsFile.exists()) {
                    typedefsFile.parentFile.mkdirs()
                    typedefsFile.writeText("")
                }
            }
        }
        // 禁用 annotations 提取任务，避免写 annotations.zip 失败
        tasks.matching {
            it.name == "extractReleaseAnnotations" ||
            it.name == "extractDebugAnnotations"
        }.configureEach {
            enabled = false
        }
    }
}

// AGP 8.x 兼容：为旧版 Flutter 插件自动注入 namespace 并提升 compileSdk
// 部分插件（如 clipboard_watcher）的 build.gradle 未声明 namespace 或使用过低的 compileSdk，
// 这里统一从 AndroidManifest.xml 提取 package 注入 namespace，并把 compileSdk 提升到 36。
// 注意：移除了 evaluationDependsOn(":app") 以便 afterEvaluate 能正常工作。
subprojects {
    pluginManager.withPlugin("com.android.library") {
        val android = extensions.findByName("android") as? com.android.build.gradle.LibraryExtension
        if (android != null) {
            // 注入 namespace（若缺失）
            if (android.namespace.isNullOrEmpty()) {
                val manifest = file("src/main/AndroidManifest.xml")
                if (manifest.exists()) {
                    val pkg = javax.xml.parsers.DocumentBuilderFactory.newInstance()
                        .newDocumentBuilder()
                        .parse(manifest)
                        .documentElement
                        .getAttribute("package")
                        .trim()
                    if (pkg.isNotEmpty()) {
                        android.namespace = pkg
                    }
                }
            }
        }
    }
    // 在项目评估完成后强制提升 compileSdk 到 36
    afterEvaluate {
        val android = extensions.findByName("android")
        if (android is com.android.build.gradle.LibraryExtension) {
            if ((android.compileSdk ?: 0) < 36) {
                android.compileSdk = 36
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
