@Library('StanUtils')
import org.stan.Utils

utils = new org.stan.Utils()

def skipExpressionTests = false
def skipRemainingStages = false
def skipCompileTests = false
def skipRebuildingBinaries = false
def skipCompileTestsAtO1 = false

/* Functions that runs a sh command and returns the stdout */
def runShell(String command){
    def output = sh (returnStdout: true, script: "${command}").trim()
    return "${output}"
}

def tagName() {
    if (env.TAG_NAME) {
        env.TAG_NAME
    } else if (env.BRANCH_NAME == 'master') {
        'nightly'
    } else {
        'unknown-tag'
    }
}

def runPerformanceTests(String testsPath, String stancFlags = ""){
    unstash 'linux-exe'

    sh """
        git clone --recursive --depth 50 https://github.com/stan-dev/performance-tests-cmdstan
    """

    writeFile(file:"performance-tests-cmdstan/cmdstan/make/local", text:"CXX=${CXX}")

    utils.checkout_pr("cmdstan", "performance-tests-cmdstan/cmdstan", params.cmdstan_pr)
    utils.checkout_pr("stan", "performance-tests-cmdstan/cmdstan/stan", params.stan_pr)
    utils.checkout_pr("math", "performance-tests-cmdstan/cmdstan/stan/lib/stan_math", params.math_pr)

    sh """
        cd performance-tests-cmdstan
        mkdir cmdstan/bin
        cp ../bin/linux-stanc cmdstan/bin/linux-stanc
        cd cmdstan; make clean-all;
    """

    if (stancFlags?.trim()) {
        sh "cd performance-tests-cmdstan/cmdstan && echo 'STANCFLAGS= $stancFlags' >> make/local"
    }

    sh """
        cd performance-tests-cmdstan/cmdstan
        echo 'O=0' >> make/local
        echo 'CXXFLAGS+=-Wall' >> make/local
        make -j${env.PARALLEL} build
    """

    if (params.run_slow_perf_tests) {
        sh """
            cd performance-tests-cmdstan
            ./runPerformanceTests.py -j${env.PARALLEL} --runs=0 --no-ignore-models ${testsPath}
        """
    } else {
        sh """
            cd performance-tests-cmdstan
            ./runPerformanceTests.py -j${env.PARALLEL} --runs=0 ${testsPath}
        """
    }
}

def cleanCheckout() {
    retry(3) {
        checkout([
            $class: 'GitSCM',
            branches: scm.branches,
            extensions: [[$class: 'CloneOption', noTags: false]],
            userRemoteConfigs: scm.userRemoteConfigs,
        ])
    }

    sh 'git clean -xffd'
}

pipeline {
    agent none
    parameters {
        booleanParam(name:"skip_end_to_end", defaultValue: false, description:"Skip end-to-end tests ")
        booleanParam(name:"skip_compile_O1", defaultValue: false, description:"Skip compile tests that run with STANCFLAGS = --O1")
        booleanParam(name:"skip_compile", defaultValue: false, description:"Skip compile tests")
        booleanParam(name:"skip_math_func_expr", defaultValue: false, description:"Skip math functions expressions test")
        booleanParam(name:"skip_ocaml_tests", defaultValue: false, description:"Skip ocaml tests")
        string(defaultValue: 'develop', name: 'cmdstan_pr',
               description: "CmdStan PR to test against. Will check out this PR in the downstream Stan repo.")
        string(defaultValue: 'develop', name: 'stan_pr',
               description: "Stan PR to test against. Will check out this PR in the downstream Stan repo.")
        string(defaultValue: 'develop', name: 'math_pr',
               description: "Math PR to test against. Will check out this PR in the downstream Math repo.")
        string(defaultValue: '', name: 'stanc_flags',
               description: "Pass STANCFLAGS to make/local, default none")
        booleanParam(name:"run_slow_perf_tests", defaultValue: false, description:"Run additional 'slow' performance tests")
        string(defaultValue: '', name: 'build_multiarch_docker_tag', description: "Docker tag for the multiarch image")
        booleanParam(name:"build_multiarch", defaultValue: false, description:"Build multiarch images even when not on 'master'")

    }
    options {
        parallelsAlwaysFailFast()
        buildDiscarder(logRotator(numToKeepStr: '20', daysToKeepStr: '30'))
        disableConcurrentBuilds(abortPrevious: true)
    }
    environment {
        CXX = 'clang++-6.0'
        PARALLEL = 4
        GIT_AUTHOR_NAME = 'Stan Jenkins'
        GIT_AUTHOR_EMAIL = 'mc.stanislaw@gmail.com'
        GIT_COMMITTER_NAME = 'Stan Jenkins'
        GIT_COMMITTER_EMAIL = 'mc.stanislaw@gmail.com'
        MULTIARCH_DOCKER_TAG = 'multiarch-ocaml-4.14-v2-and-cmdliner'
    }
    stages {
        stage('Verify changes') {
            agent {
                dockerfile {
                    filename 'scripts/docker/debian/Dockerfile'
                    dir '.'
                    label 'linux'
                    args '--entrypoint=\'\''
                    additionalBuildArgs  '--build-arg PUID=\$(id -u) --build-arg PGID=\$(id -g)'
                }
            }
            steps {
                script {
                    cleanCheckout()

                    stash 'Stanc3Setup'

                    def stanMathSigs = ['test/integration/signatures/stan_math_signatures.t'].join(" ")
                    skipExpressionTests = utils.verifyChanges(stanMathSigs, "master")

                    def runTestPaths = ['src', 'test/integration/good', 'test/stancjs'].join(" ")
                    skipRemainingStages = utils.verifyChanges(runTestPaths, "master")

                    def compileTests = ['test/integration/good'].join(" ")
                    skipCompileTests = utils.verifyChanges(compileTests, "master")

                    def compileTestsAtO1 = ['test/integration/good/compiler-optimizations'].join(" ")
                    skipCompileTestsAtO1 = utils.verifyChanges(compileTestsAtO1, "master")

                    def sourceCodePaths = ['src', 'Jenkinsfile'].join(" ")
                    skipRebuildingBinaries = utils.verifyChanges(sourceCodePaths, "master")
                }
            }
            post { always { runShell("rm -rf ./*") }}
        }


        stage("OCaml build & tests") {
            parallel {
                stage("Build") {
                    when {
                        beforeAgent true
                        expression {
                            anyOf {
                                !skipRebuildingBinaries
                                !skipRemainingStages
                            }
                        }
                    }
                    agent {
                        dockerfile {
                            filename 'scripts/docker/static/Dockerfile'
                            dir '.'
                            label 'linux && triqs'
                            args '--group-add=987 --group-add=980 --group-add=988 --entrypoint=\'\''
                            additionalBuildArgs  '--build-arg PUID=\$(id -u) --build-arg PGID=\$(id -g)'
                        }
                    }
                    steps {
                        dir("${env.WORKSPACE}/linux"){
                            cleanCheckout()
                            runShell("""
                                eval \$(opam env)
                                dune subst
                                dune build @install --profile static --root=.
                            """)
                            sh "mkdir -p bin && mv `find _build -name stanc.exe` bin/linux-stanc"
                            stash name:'linux-exe', includes:'bin/*'
                        }
                    }
                    post {always { runShell("rm -rf ${env.WORKSPACE}/linux/*")}}
                }
                stage("Code formatting") {
                    when {
                        beforeAgent true
                        expression {
                            !skipRemainingStages
                        }
                    }
                    agent {
                        dockerfile {
                            filename 'scripts/docker/debian/Dockerfile'
                            dir '.'
                            label 'linux'
                            args '--entrypoint=\'\''
                            additionalBuildArgs  '--build-arg PUID=\$(id -u) --build-arg PGID=\$(id -g)'
                        }
                    }
                    steps {
                        unstash "Stanc3Setup"
                        sh """
                            eval \$(opam env)
                            make format  ||
                            (
                                set +x &&
                                echo "The source code was not formatted. Please run 'make format; dune promote' and push the changes." &&
                                echo "Please consider installing the pre-commit git hook for formatting with the above command." &&
                                echo "Our hook can be installed with bash ./scripts/hooks/install_hooks.sh" &&
                                exit 1;
                            )
                        """
                    }
                    post { always { runShell("rm -rf ./*") }}
                }

                stage("Dune tests") {
                    when {
                        beforeAgent true
                        allOf {
                            expression {
                                !skipRemainingStages
                            }
                            expression {
                                !params.skip_ocaml_tests
                            }
                        }
                    }
                    agent {
                        dockerfile {
                            filename 'scripts/docker/debian/Dockerfile'
                            dir '.'
                            label 'linux'
                            args '--entrypoint=\'\''
                            additionalBuildArgs  '--build-arg PUID=\$(id -u) --build-arg PGID=\$(id -g)'
                        }
                    }
                    steps {
                        dir("${env.WORKSPACE}/dune-tests"){
                            unstash "Stanc3Setup"
                            runShell("""
                                eval \$(opam env)
                                BISECT_FILE=\$(pwd)/bisect dune runtest --instrument-with bisect_ppx --force --root=.
                            """)

                            sh """
                                eval \$(opam env)
                                bisect-ppx-report summary --expect src/ --do-not-expect src/stancjs/
                                bisect-ppx-report coveralls coverage.json --service-name jenkins --service-job-id $BUILD_ID --expect src/ --do-not-expect src/stancjs/
                            """

                            withCredentials([usernamePassword(credentialsId: 'stan-stanc3-codecov-token', usernameVariable: 'DUMMY_USERNAME', passwordVariable: 'CODECOV_TOKEN')]) {
                                sh """
                                    curl -Os https://uploader.codecov.io/v0.3.2/linux/codecov

                                    chmod +x codecov
                                    ./codecov -v -C \$(git rev-parse HEAD)
                                """
                            }
                        }
                    }
                    post { always { runShell("rm -rf ${env.WORKSPACE}/dune-tests/*") }}
                }
                stage("stancjs tests") {
                    when {
                        beforeAgent true
                        allOf {
                            expression {
                                !skipRemainingStages
                            }
                            expression {
                                !params.skip_ocaml_tests
                            }
                        }
                    }
                    agent {
                        dockerfile {
                            filename 'scripts/docker/debian/Dockerfile'
                            dir '.'
                            label 'linux'
                            args '--entrypoint=\'\''
                            additionalBuildArgs  '--build-arg PUID=\$(id -u) --build-arg PGID=\$(id -g)'
                        }
                    }
                    steps {
                        dir("${env.WORKSPACE}/stancjs-tests"){
                            unstash "Stanc3Setup"
                            runShell("""
                                node --version
                                eval \$(opam env)
                                dune build @runjstest --root=.
                            """)
                        }
                    }
                    post { always { runShell("rm -rf ${env.WORKSPACE}/stancjs-tests/*") }}
                }
            }
        }

        stage("CmdStan & Math tests") {
            parallel {

                stage("Compile tests - good") {
                    when {
                        beforeAgent true
                        allOf {
                          expression {
                            !skipCompileTests
                          }
                          expression {
                            !params.skip_compile
                          }
                        }
                    }
                    agent {
                        docker {
                            image 'stanorg/ci:gpu'
                            label 'linux'
                        }
                    }
                    steps {
                        dir("${env.WORKSPACE}/compile-tests-good"){
                            unstash "Stanc3Setup"
                            script {
                                runPerformanceTests("../test/integration/good", params.stanc_flags)
                            }

                            xunit([GoogleTest(
                                deleteOutputFiles: false,
                                failIfNotNew: true,
                                pattern: 'performance-tests-cmdstan/performance.xml',
                                skipNoTestFiles: false,
                                stopProcessingIfError: false)
                            ])
                        }
                    }
                    post { always { runShell("rm -rf ${env.WORKSPACE}/compile-tests-good/*") }}
                }

                stage("Compile tests - example-models") {
                    when {
                        beforeAgent true
                        allOf {
                          expression {
                            !skipCompileTests
                          }
                          expression {
                            !params.skip_compile
                          }
                        }
                    }
                    agent {
                        docker {
                            image 'stanorg/ci:gpu'
                            label 'linux'
                        }
                    }
                    steps {
                        dir("${env.WORKSPACE}/compile-tests-example"){
                            script {
                                unstash "Stanc3Setup"
                                runPerformanceTests("example-models", params.stanc_flags)
                            }

                            xunit([GoogleTest(
                                deleteOutputFiles: false,
                                failIfNotNew: true,
                                pattern: 'performance-tests-cmdstan/performance.xml',
                                skipNoTestFiles: false,
                                stopProcessingIfError: false)
                            ])
                        }
                    }
                    post { always { runShell("rm -rf ${env.WORKSPACE}/compile-tests-example/*") }}
                }

                stage("Compile tests - good at O=1") {
                    when {
                        beforeAgent true
                        allOf {
                          expression {
                            !skipCompileTestsAtO1
                          }
                          expression {
                            !params.skip_compile_O1
                          }
                        }
                    }
                    agent {
                        docker {
                            image 'stanorg/ci:gpu'
                            label 'linux'
                        }
                    }
                    steps {
                        dir("${env.WORKSPACE}/compile-good-O1"){
                            unstash "Stanc3Setup"
                            script {
                                runPerformanceTests("../test/integration/good", "--O1")
                            }

                            xunit([GoogleTest(
                                deleteOutputFiles: false,
                                failIfNotNew: true,
                                pattern: 'performance-tests-cmdstan/performance.xml',
                                skipNoTestFiles: false,
                                stopProcessingIfError: false)
                            ])
                        }
                    }
                    post { always { runShell("rm -rf ${env.WORKSPACE}/compile-good-O1/*") }}
                }

                stage("Compile tests - example-models at O=1") {
                    when {
                        beforeAgent true
                        allOf {
                          expression {
                            !skipCompileTestsAtO1
                          }
                          expression {
                            !params.skip_compile_O1
                          }
                        }
                    }
                    agent {
                        docker {
                            image 'stanorg/ci:gpu'
                            label 'linux'
                        }
                    }
                    steps {
                        dir("${env.WORKSPACE}/compile-example-O1"){
                            script {
                                unstash "Stanc3Setup"
                                runPerformanceTests("example-models", "--O1")
                            }

                            xunit([GoogleTest(
                                deleteOutputFiles: false,
                                failIfNotNew: true,
                                pattern: 'performance-tests-cmdstan/performance.xml',
                                skipNoTestFiles: false,
                                stopProcessingIfError: false)
                            ])
                        }
                    }
                    post { always { runShell("rm -rf ${env.WORKSPACE}/compile-example-O1/*") }}
                }

                stage("Model end-to-end tests") {
                    when {
                        beforeAgent true
                        allOf {
                         expression {
                            !skipCompileTests
                         }
                         expression {
                            !params.skip_end_to_end
                         }
                        }
                    }
                    agent {
                        docker {
                            image 'stanorg/ci:gpu'
                            label 'linux'
                        }
                    }
                    steps {
                        dir("${env.WORKSPACE}/compile-end-to-end"){
                            script {
                                unstash "Stanc3Setup"
                                unstash 'linux-exe'
                                sh """
                                    git clone --recursive --depth 50 https://github.com/stan-dev/performance-tests-cmdstan
                                """
                                utils.checkout_pr("cmdstan", "performance-tests-cmdstan/cmdstan", params.cmdstan_pr)
                                utils.checkout_pr("stan", "performance-tests-cmdstan/cmdstan/stan", params.stan_pr)
                                utils.checkout_pr("math", "performance-tests-cmdstan/cmdstan/stan/lib/stan_math", params.math_pr)
                                sh """
                                    cd performance-tests-cmdstan
                                    git show HEAD --stat
                                    echo "example-models/regression_tests/mother.stan" > all.tests
                                    cat known_good_perf_all.tests >> all.tests
                                    echo "" >> all.tests
                                    cat shotgun_perf_all.tests >> all.tests
                                    cat all.tests
                                    echo "CXXFLAGS+=-march=core2" > cmdstan/make/local
                                    echo "PRECOMPILED_HEADERS=false" >> cmdstan/make/local
                                    cd cmdstan; make clean-all; git show HEAD --stat; cd ..
                                    CXX="${CXX}" ./compare-compilers.sh "--tests-file all.tests --num-samples=10 -j${env.PARALLEL}" "\$(readlink -f ../bin/linux-stanc)"
                                """
                            }

                            xunit([GoogleTest(
                                deleteOutputFiles: false,
                                failIfNotNew: true,
                                pattern: 'performance-tests-cmdstan/performance.xml',
                                skipNoTestFiles: false,
                                stopProcessingIfError: false)
                            ])

                            archiveArtifacts 'performance-tests-cmdstan/performance.xml'

                        }
                    }
                    post { always { runShell("rm -rf ${env.WORKSPACE}/compile-end-to-end/*") }}
                }

                stage("Model end-to-end tests at O=1") {
                    when {
                        beforeAgent true
                        allOf {
                         expression {
                            !params.skip_end_to_end
                         }
                         expression {
                            !skipCompileTestsAtO1
                         }
                        }
                    }
                    agent {
                        docker {
                            image 'stanorg/ci:gpu'
                            label 'linux'
                        }
                    }
                    steps {
                        dir("${env.WORKSPACE}/compile-end-to-end-O=1"){
                            script {
                                unstash "Stanc3Setup"
                                unstash 'linux-exe'
                                sh """
                                    git clone --recursive --depth 50 https://github.com/stan-dev/performance-tests-cmdstan
                                """
                                utils.checkout_pr("cmdstan", "performance-tests-cmdstan/cmdstan", params.cmdstan_pr)
                                utils.checkout_pr("stan", "performance-tests-cmdstan/cmdstan/stan", params.stan_pr)
                                utils.checkout_pr("math", "performance-tests-cmdstan/cmdstan/stan/lib/stan_math", params.math_pr)
                                sh """
                                    cd performance-tests-cmdstan
                                    git show HEAD --stat
                                    echo "example-models/regression_tests/mother.stan" > all.tests
                                    cat optimizer.tests >> all.tests
                                    echo "" >> all.tests
                                    cat known_good_perf_all.tests >> all.tests
                                    echo "" >> all.tests
                                    cat shotgun_perf_all.tests >> all.tests
                                    cat all.tests
                                    echo "CXXFLAGS+=-march=core2" > cmdstan/make/local
                                    echo "PRECOMPILED_HEADERS=false" >> cmdstan/make/local
                                    cd cmdstan; make clean-all; git show HEAD --stat; cd ..
                                    CXX="${CXX}" ./compare-optimizer.sh "--tests-file all.tests --num-samples=10 -j${env.PARALLEL}" "--O1" "\$(readlink -f ../bin/linux-stanc)"
                                """
                            }

                            xunit([GoogleTest(
                                deleteOutputFiles: false,
                                failIfNotNew: true,
                                pattern: 'performance-tests-cmdstan/performance.xml',
                                skipNoTestFiles: false,
                                stopProcessingIfError: false)
                            ])

                            archiveArtifacts 'performance-tests-cmdstan/performance.xml'
                        }
                    }
                    post { always { runShell("rm -rf ${env.WORKSPACE}/compile-end-to-end-O=1/*") }}
                }

                stage('Math functions expressions test') {
                    when {
                        beforeAgent true
                        allOf {
                            expression {
                                !skipRemainingStages
                            }
                            expression {
                                !skipExpressionTests
                            }
                            expression {
                                !params.skip_math_func_expr
                            }
                        }
                    }
                    agent {
                        docker {
                            image 'stanorg/ci:gpu'
                            label 'linux'
                        }
                    }
                    steps {
                        dir("${env.WORKSPACE}/compile-expressions"){
                            unstash "Stanc3Setup"
                            unstash 'linux-exe'
                            script {
                                sh """
                                    git clone --recursive https://github.com/stan-dev/math.git
                                """
                                utils.checkout_pr("math", "math", params.math_pr)
                                sh """
                                    cp bin/linux-stanc math/test/expressions/stanc
                                """

                                dir("math") {
                                    sh """
                                        echo O=0 >> make/local
                                        echo "CXX=${env.CXX} -Werror " >> make/local
                                    """
                                    withEnv(['PATH+TBB=./lib/tbb']) {
                                        try { sh "./runTests.py -j${env.PARALLEL} test/expressions" }
                                        finally { junit 'test/**/*.xml' }
                                    }
                                }
                            }
                        }
                    }
                    post { always { runShell("rm -rf ${env.WORKSPACE}/compile-expressions/*") }}
                }
            }
        }

        stage('Build and push multiarch docker image') {
            when {
                beforeAgent true
                expression {
                    params.build_multiarch_docker_tag != ""
                }
            }
            agent {
                dockerfile {
                    filename 'scripts/docker/builder/Dockerfile'
                    dir '.'
                    label 'linux && triqs'
                    args '--group-add=987 --group-add=980 --group-add=988 --entrypoint=\'\' -v /var/run/docker.sock:/var/run/docker.sock'
                    additionalBuildArgs  '--build-arg PUID=\$(id -u) --build-arg PGID=\$(id -g)'
                }
            }
            environment { DOCKER_TOKEN = credentials('aada4f7b-baa9-49cf-ac97-5490620fce8a') }
            steps {
                script {
                    retry(3) { checkout scm }
                    sh '''
                        docker run --rm --privileged multiarch/qemu-user-static --reset -p yes

                        docker buildx create --name stanc3_builder
                        docker buildx use stanc3_builder

                        docker login --username stanorg --password "${DOCKER_TOKEN}"

                        cd scripts/docker/multiarch

                        docker buildx build -t stanorg/stanc3:$build_multiarch_docker_tag \
                        --platform linux/arm/v6,linux/arm/v7,linux/arm64,linux/ppc64le,linux/mips64le,linux/s390x \
                        --build-arg PUID=$(id -u) \
                        --build-arg PGID=$(id -g) \
                        --progress=plain --push .
                    '''
                }
            }
            post {
                always {
                    deleteDir()
                }
            }
        }


        stage('Build binaries') {
            parallel {
                stage("Build MacOS binaries") {
                    agent none
                    when {
                        beforeAgent true
                        expression { !skipRebuildingBinaries }
                    }
                    stages {
                        stage("Build & test MacOS x86 binary") {
                            agent { label 'osx && intel' }
                            steps {
                                dir("${env.WORKSPACE}/osx-x86"){
                                    cleanCheckout()
                                    withEnv(['SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX10.11.sdk', 'MACOSX_DEPLOYMENT_TARGET=10.11']) {
                                        runShell("""
                                            export PATH=/Users/jenkins/brew/bin:\$PATH
                                            eval \$(opam env --switch=stanc-4.14.1 --set-switch)
                                            opam update || true
                                            bash -x scripts/install_build_deps.sh
                                            dune subst
                                            dune build @install --root=.
                                        """)
                                    }
                                    sh "mkdir -p bin && mv `find _build -name stanc.exe` bin/mac-x86-stanc"
                                    stash name:'mac-x86-exe', includes:'bin/*'
                                }
                            }
                            post { always { runShell("rm -rf ${env.WORKSPACE}/osx-x86/*") }}
                        }

                        stage("Build & test MacOS arm64 binary") {
                            agent { label 'osx && m1' }
                            steps {
                                dir("${env.WORKSPACE}/osx-arm64"){
                                    cleanCheckout()
                                    withEnv(['SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX11.0.sdk', 'MACOSX_DEPLOYMENT_TARGET=11.0']) {
                                        runShell("""
                                            export PATH=/Users/jenkins/brew/bin:\$PATH
                                            eval \$(opam env --switch=stanc-4.14.1 --set-switch)
                                            opam update || true
                                            bash -x scripts/install_build_deps.sh
                                            dune subst
                                            dune build @install --root=.
                                        """)
                                    }
                                    sh "mkdir -p bin && mv `find _build -name stanc.exe` bin/mac-arm64-stanc"
                                    stash name:'mac-arm64-exe', includes:'bin/*'
                                }
                            }
                            post { always { runShell("rm -rf ${env.WORKSPACE}/osx-arm64/*") }}
                        }

                        stage('Build MacOS fat binary') {
                            agent { label 'osx && m1' }
                            steps {
                                dir("${env.WORKSPACE}/osx-universal"){
                                    unstash 'mac-arm64-exe'
                                    unstash 'mac-x86-exe'
                                    withEnv(['SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX11.0.sdk', 'MACOSX_DEPLOYMENT_TARGET=11.0']) {
                                        sh "lipo -create bin/mac-x86-stanc bin/mac-arm64-stanc -output bin/mac-stanc"
                                    }
                                    sh "lipo -archs bin/mac-stanc"
                                    stash name:'mac-exe', includes:'bin/mac-stanc'
                                }
                            }
                            post { always { runShell("rm -rf ${env.WORKSPACE}/osx-universal/*") }}
                        }
                    }
                }

                stage("Build stanc.js") {
                    when {
                        beforeAgent true
                        expression {
                            !skipRebuildingBinaries
                        }
                    }
                    agent {
                        dockerfile {
                            filename 'scripts/docker/debian/Dockerfile'
                            dir '.'
                            label 'linux && triqs'
                            args '--group-add=987 --group-add=980 --group-add=988 --entrypoint=\'\''
                            additionalBuildArgs  '--build-arg PUID=\$(id -u) --build-arg PGID=\$(id -g)'
                        }
                    }
                    steps {
                        dir("${env.WORKSPACE}/stancjs"){
                            cleanCheckout()
                            runShell("""
                                eval \$(opam env)
                                dune subst
                                dune build --root=. --profile release src/stancjs
                            """)
                            sh "mkdir -p bin && mv `find _build -name stancjs.bc.js` bin/stanc.js"
                            sh "mv `find _build -name index.html` bin/load_stanc.html"
                            runShell("""
                                eval \$(opam env)
                                dune build --force --profile=dev --root=. src/stancjs
                            """)
                            sh "mv `find _build -name stancjs.bc.js` bin/stanc-pretty.js"
                            stash name:'js-exe', includes:'bin/*'
                        }
                    }
                    post {always { runShell("rm -rf ${env.WORKSPACE}/stancjs/*")}}
                }

                stage("Build & test a static Linux mips64el binary") {
                    when {
                        beforeAgent true
                        allOf {
                            expression { !skipRebuildingBinaries }
                            anyOf { buildingTag(); branch 'master'; expression { params.build_multiarch } }
                        }
                    }
                    agent {
                        dockerfile {
                            filename 'scripts/docker/static/Dockerfile'
                            dir '.'
                            label 'linux && triqs'
                            args '--group-add=987 --group-add=980 --group-add=988 --entrypoint=\'\' -v /var/run/docker.sock:/var/run/docker.sock'
                            additionalBuildArgs  '--build-arg PUID=\$(id -u) --build-arg PGID=\$(id -g)'
                        }
                    }
                    steps {
                        dir("${env.WORKSPACE}/linux-mips64el"){
                            cleanCheckout()

                            sh """
                                eval \$(opam env)
                                bash -x scripts/build_multiarch_stanc3.sh mips64el ${MULTIARCH_DOCKER_TAG}
                            """

                            sh "mkdir -p bin && mv `find _build -name stanc.exe` bin/linux-mips64el-stanc"

                            stash name:'linux-mips64el-exe', includes:'bin/*'
                        }
                    }
                    post {always { runShell("rm -rf ${env.WORKSPACE}/linux-mips64el/*")}}
                }

                stage("Build & test a static Linux ppc64el binary") {
                    when {
                        beforeAgent true
                        allOf {
                            expression { !skipRebuildingBinaries }
                            anyOf { buildingTag(); branch 'master'; expression { params.build_multiarch } }
                        }
                    }
                    agent {
                        dockerfile {
                            filename 'scripts/docker/static/Dockerfile'
                            dir '.'
                            label 'linux && triqs'
                            args '--group-add=987 --group-add=980 --group-add=988 --entrypoint=\'\' -v /var/run/docker.sock:/var/run/docker.sock'
                            additionalBuildArgs  '--build-arg PUID=\$(id -u) --build-arg PGID=\$(id -g)'
                        }
                    }
                    steps {
                        dir("${env.WORKSPACE}/linux-ppc64el"){
                            cleanCheckout()
                            sh """
                                eval \$(opam env)
                                bash -x scripts/build_multiarch_stanc3.sh ppc64el ${MULTIARCH_DOCKER_TAG}
                            """
                            sh "mkdir -p bin && mv `find _build -name stanc.exe` bin/linux-ppc64el-stanc"
                            stash name:'linux-ppc64el-exe', includes:'bin/*'
                        }
                    }
                    post {always { runShell("rm -rf ${env.WORKSPACE}/linux-ppc64el/*")}}
                }

                stage("Build & test a static Linux s390x binary") {
                    when {
                        beforeAgent true
                        allOf {
                            expression { !skipRebuildingBinaries }
                            anyOf { buildingTag(); branch 'master'; expression { params.build_multiarch } }
                        }
                    }
                    agent {
                        dockerfile {
                            filename 'scripts/docker/static/Dockerfile'
                            dir '.'
                            label 'linux && triqs'
                            args '--group-add=987 --group-add=980 --group-add=988 --entrypoint=\'\' -v /var/run/docker.sock:/var/run/docker.sock'
                            additionalBuildArgs  '--build-arg PUID=\$(id -u) --build-arg PGID=\$(id -g)'
                        }
                    }
                    steps {
                        dir("${env.WORKSPACE}/linux-s390x"){
                            cleanCheckout()
                            sh """
                                eval \$(opam env)
                                bash -x scripts/build_multiarch_stanc3.sh s390x ${MULTIARCH_DOCKER_TAG}
                            """
                            sh "mkdir -p bin && mv `find _build -name stanc.exe` bin/linux-s390x-stanc"
                            stash name:'linux-s390x-exe', includes:'bin/*'
                        }
                    }
                    post {always { runShell("rm -rf ${env.WORKSPACE}/linux-s390x/*")}}
                }

                stage("Build & test a static Linux arm64 binary") {
                    when {
                        beforeAgent true
                        allOf {
                            expression { !skipRebuildingBinaries }
                            anyOf { buildingTag(); branch 'master'; expression { params.build_multiarch } }
                        }
                    }
                    agent {
                        dockerfile {
                            filename 'scripts/docker/static/Dockerfile'
                            dir '.'
                            label 'linux && triqs'
                            args '--group-add=987 --group-add=980 --group-add=988 --entrypoint=\'\' -v /var/run/docker.sock:/var/run/docker.sock'
                            additionalBuildArgs  '--build-arg PUID=\$(id -u) --build-arg PGID=\$(id -g)'
                        }
                    }
                    steps {
                        dir("${env.WORKSPACE}/linux-arm64"){
                            cleanCheckout()
                            sh """
                                eval \$(opam env)
                                bash -x scripts/build_multiarch_stanc3.sh arm64 ${MULTIARCH_DOCKER_TAG}
                            """
                            sh "mkdir -p bin && mv `find _build -name stanc.exe` bin/linux-arm64-stanc"
                            stash name:'linux-arm64-exe', includes:'bin/*'
                        }
                    }
                    post {always { runShell("rm -rf ${env.WORKSPACE}/linux-arm64/*")}}
                }

                stage("Build & test a static Linux armhf binary") {
                    when {
                        beforeAgent true
                        allOf {
                            expression { !skipRebuildingBinaries }
                            anyOf { buildingTag(); branch 'master'; expression { params.build_multiarch } }
                        }
                    }
                    agent {
                        dockerfile {
                            filename 'scripts/docker/static/Dockerfile'
                            dir '.'
                            label 'linux && triqs'
                            args '--group-add=987 --group-add=980 --group-add=988 --entrypoint=\'\' -v /var/run/docker.sock:/var/run/docker.sock'
                            additionalBuildArgs  '--build-arg PUID=\$(id -u) --build-arg PGID=\$(id -g)'
                        }
                    }
                    steps {
                        dir("${env.WORKSPACE}/linux-armhf"){
                            cleanCheckout()
                            sh """
                                eval \$(opam env)
                                bash -x scripts/build_multiarch_stanc3.sh armhf ${MULTIARCH_DOCKER_TAG}
                            """
                            sh "mkdir -p bin && mv `find _build -name stanc.exe` bin/linux-armhf-stanc"
                            stash name:'linux-armhf-exe', includes:'bin/*'
                        }
                    }
                    post {always { runShell("rm -rf ${env.WORKSPACE}/linux-armhf/*")}}
                }

                stage("Build & test a static Linux armel binary") {
                    when {
                        beforeAgent true
                        allOf {
                            expression { !skipRebuildingBinaries }
                            anyOf { buildingTag(); branch 'master'; expression { params.build_multiarch } }
                        }
                    }
                    agent {
                        dockerfile {
                            filename 'scripts/docker/static/Dockerfile'
                            dir '.'
                            label 'linux && triqs'
                            args '--group-add=987 --group-add=980 --group-add=988 --entrypoint=\'\' -v /var/run/docker.sock:/var/run/docker.sock'
                            additionalBuildArgs  '--build-arg PUID=\$(id -u) --build-arg PGID=\$(id -g)'
                        }
                    }
                    steps {
                        dir("${env.WORKSPACE}/linux-armel"){
                            cleanCheckout()
                            sh """
                                eval \$(opam env)
                                bash -x scripts/build_multiarch_stanc3.sh armel ${MULTIARCH_DOCKER_TAG}
                            """
                            sh "mkdir -p bin && mv `find _build -name stanc.exe` bin/linux-armel-stanc"
                            stash name:'linux-armel-exe', includes:'bin/*'
                        }
                    }
                    post {always { runShell("rm -rf ${env.WORKSPACE}/linux-armel/*")}}
                }

                // Cross compiling for windows on debian
                stage("Build & test static Windows binary") {
                    when {
                        beforeAgent true
                        expression {
                            !skipRebuildingBinaries
                        }
                    }
                    agent {
                        dockerfile {
                            filename 'scripts/docker/debian-windows/Dockerfile'
                            dir '.'
                            label 'linux && triqs'
                            args '--group-add=987 --group-add=980 --group-add=988 --entrypoint=\'\''
                            additionalBuildArgs  '--build-arg PUID=\$(id -u) --build-arg PGID=\$(id -g)'
                        }
                    }
                    steps {
                        dir("${env.WORKSPACE}/windows"){
                            cleanCheckout()
                            runShell("""
                                eval \$(opam env)
                                dune subst
                                dune build -x windows --root=.
                            """)
                            sh "mkdir -p bin && mv _build/default.windows/src/stanc/stanc.exe bin/windows-stanc"
                            stash name:'windows-exe', includes:'bin/*'
                        }
                    }
                    post {always { runShell("rm -rf ${env.WORKSPACE}/windows/*")}}
                }

            }
        }

        stage('Check binary version'){
            when {
                beforeAgent true
                expression { !skipRebuildingBinaries }
            }
            agent {
                dockerfile {
                    filename 'scripts/docker/publish/Dockerfile'
                    dir '.'
                    label 'linux'
                    args '--group-add=987 --group-add=980 --group-add=988 --entrypoint=\'\''
                    additionalBuildArgs  '--build-arg PUID=\$(id -u) --build-arg PGID=\$(id -g)'
                }
            }
            steps {
                sh "rm -r bin/ || true"

                dir("bin"){
                    unstash 'linux-exe'
                    sh "bin/linux-stanc --version"
                }
            }
        }

        stage("Release tag and publish binaries") {
            when {
                beforeAgent true
                allOf {
                    expression { !skipRemainingStages }
                    expression { !skipRebuildingBinaries }
                    anyOf { buildingTag(); branch 'master' }
                }
            }
            agent {
                dockerfile {
                    filename 'scripts/docker/publish/Dockerfile'
                    dir '.'
                    label 'linux'
                    args '--group-add=987 --group-add=980 --group-add=988 --entrypoint=\'\''
                    additionalBuildArgs  '--build-arg PUID=\$(id -u) --build-arg PGID=\$(id -g)'
                }
            }
            environment { GITHUB_TOKEN = credentials('6e7c1e8f-ca2c-4b11-a70e-d934d3f6b681') }
            steps {
                retry(3) {
                    sh "rm -r bin/ || true"

                    dir("bin"){
                        unstash 'windows-exe'
                        unstash 'linux-exe'
                        unstash 'mac-exe'
                        unstash 'mac-arm64-exe'
                        unstash 'mac-x86-exe'
                        unstash 'linux-mips64el-exe'
                        unstash 'linux-ppc64el-exe'
                        unstash 'linux-s390x-exe'
                        unstash 'linux-arm64-exe'
                        unstash 'linux-armhf-exe'
                        unstash 'linux-armel-exe'
                        unstash 'js-exe'

                        runShell("""
                            gh release delete ${tagName()} --cleanup-tag -y || true
                            gh release create ${tagName()} --latest --target master --notes "\$(git log --pretty=format:'nightly: %h %s' -n 1)" ./bin/*
                        """)

                        // Update stanc.js in StanHeaders
                        withCredentials([usernamePassword(credentialsId: 'a630aebc-6861-4e69-b497-fd7f496ec46b', usernameVariable: 'GIT_USERNAME', passwordVariable: 'GIT_PASSWORD')]) {
                            sh """#!/bin/bash
                                set -e

                                git clone https://${GIT_USERNAME}:${GIT_PASSWORD}@github.com/stan-dev/rstan.git
                                git config user.email "mc.stanislaw@gmail.com"
                                git config user.name "Stan Jenkins"
                                git config auth.token ${GITHUB_TOKEN}

                                rm rstan/StanHeaders/inst/stanc.js
                                cp ./bin/stanc.js rstan/StanHeaders/inst/stanc.js
                                git -C rstan add StanHeaders/inst/stanc.js
                                git -C rstan commit -m "Update stanc.js to ${tagName()}"
                                git -C rstan push https://${GIT_USERNAME}:${GIT_PASSWORD}@github.com/stan-dev/rstan.git develop
                            """
                        }
                    }
                }
            }
            post {
                failure {
                    archiveArtifacts 'bin/*'
                }
            }
        }

        stage('Upload odoc') {
            when {
                beforeAgent true
                branch 'master'
            }
            agent {
                dockerfile {
                    filename 'scripts/docker/static/Dockerfile'
                    dir '.'
                    label 'linux'
                    args '--entrypoint=\'\''
                    additionalBuildArgs  '--build-arg PUID=\$(id -u) --build-arg PGID=\$(id -g)'
                }
            }
            steps {
                retry(3) {
                    checkout([$class: 'GitSCM',
                        branches: [[name: '*/master'], [name: '*/gh-pages']],
                        doGenerateSubmoduleConfigurations: false,
                        extensions: [],
                        submoduleCfg: [],
                        userRemoteConfigs: [[url: "https://github.com/stan-dev/stanc3.git", credentialsId: 'a630aebc-6861-4e69-b497-fd7f496ec46b']]]
                    )
                }

                // Checkout gh-pages as a test so we build docs from this branch
                runShell("""
                    git remote set-branches --add origin gh-pages || true
                    git checkout --track origin/gh-pages || true
                    git remote set-branches --add origin master || true
                    git checkout origin/master || true
                """)

                // Build docs
                runShell("""
                     eval \$(opam env)
                     dune build @doc
                """)

                // Copy static assets to doc
                runShell("""
                    mkdir -p doc
                    cp -r ./_build/default/_doc/_html/* doc/
                """)

                // Commit changes to the repository gh-pages branch
                withCredentials([usernamePassword(credentialsId: 'a630aebc-6861-4e69-b497-fd7f496ec46b', usernameVariable: 'GIT_USERNAME', passwordVariable: 'GIT_PASSWORD')]) {
                    sh """#!/bin/bash
                        set -e

                        git checkout --detach
                        git branch -D gh-pages
                        git push https://${GIT_USERNAME}:${GIT_PASSWORD}@github.com/stan-dev/stanc3.git :gh-pages

                        git checkout --orphan gh-pages
                        git add -f doc
                        git commit -m "auto generated docs from Jenkins"
                        git subtree push --prefix doc/ https://${GIT_USERNAME}:${GIT_PASSWORD}@github.com/stan-dev/stanc3.git gh-pages
                        ls -A1 | xargs rm -rf
                    """
                }

            }
        }

    }
    post {
      always {
          script {
            utils.mailBuildResults()
          }
        }
    }
}
