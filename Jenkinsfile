pipeline {
    agent {
        kubernetes {
            label 'kube_small'
            defaultContainer 'jnlp'
        }
    }
    tools {
        nodejs 'nodejs'
    }

    parameters {
        string(name: 'BRANCH_NAME', defaultValue: 'master', description: 'Git branch to build')
        choice(name: 'DEPLOY_ENV', choices: ['test', 'prod'], description: 'Deployment environment')
        string(name: 'DOCKER_HUB_REPO', defaultValue: 'daggu1997/jenkins', description: 'Enter the Docker Hub image name (e.g., daggu1997/kubejenkins)')
    }

    environment {
        DOCKER_HUB_CREDENTIALS_ID = 'docker'
        DEP_CHECK_PROJECT = "${env.JOB_NAME}"
        DEP_CHECK_OUT_DIR = 'reports'
        GITHUB_CREDENTIALS_ID = 'github'
        GITHUB_REPO = 'Rajendra0609/Doc_jen'
        GITHUB_API_URL = 'https://api.github.com'
        SLACK_CHANNEL = '#build-notifications'
        SLACK_CREDENTIALS_ID = 'slack-token'
        EMAIL_CREDENTIALS_ID = 'gmail'
    }

    options {
        timeout(time: 90, unit: 'MINUTES')
        timestamps()
        retry(0)
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10', artifactNumToKeepStr: '5'))
    }

    stages {
        stage('build') {
            steps {
                script {
                    echo "There is empty to build the project"
                }
            }
        }
        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('SonarQube') {  
                    sh '''
                    sonar-scanner \
                    -Dsonar.projectKey=my_project_key \
                    -Dsonar.sources=src \
                    -Dsonar.host.url=$SONAR_HOST_URL \
                    -Dsonar.login=$SONAR_AUTH_TOKEN > sonar-scanner.log 2>&1
                    '''
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'sonar-scanner.log', allowEmptyArchive: true
                    script {
                        def qg = waitForQualityGate(timeout: 10)
                        echo "Quality Gate status: ${qg.status}"
                        // If the Quality Gate fails, abort the build.
                        if (qg.status != 'OK') {
                            error "Pipeline aborted due to Quality Gate failure: ${qg.status}"
                        } else {
                            echo "Quality Gate passed successfully."
                        }
                    }
                }
            }
        }
        stage('Lynis Security Scan') {
            steps {
                script {
                    try {
                        sh '''
                            mkdir -p artifacts/lynis
                            lynis audit system | ansi2html > artifacts/lynis/lynis-report.html
                        '''
                        echo "Lynis report path: ${env.WORKSPACE}/artifacts/lynis/lynis-report.html"
                        archiveArtifacts artifacts: 'artifacts/lynis/lynis-report.html', allowEmptyArchive: true
                    } catch (Exception e) {
                        error("Lynis Security Scan failed: ${e.message}")
                    }
                }
            }
        }
        stage('OWASP FS SCAN') {
            agent {
                label 'doc'
            }
            steps {
                script {
                    dependencyCheck additionalArguments: '--scan ./ --format HTML --format XML', odcInstallation: 'dpcheck'
                    dependencyCheckPublisher pattern: '**/dependency-check-report.xml'
                    archiveArtifacts artifacts: '**/dependency-check-report.html', allowEmptyArchive: true
                }
            }
        }
        stage('Build Docker Image') {
            steps {
                script {
                    def dockerfileName = ''
                    try {
                        dockerfileName = input(
                            id: 'userInput', message: 'Enter Dockerfile name (leave blank for default)', parameters: [
                                string(defaultValue: '', description: 'Dockerfile name (e.g., Dockerfile1)', name: 'DOCKERFILE_NAME')
                            ], 
                            submitter: '', 
                            timeout: 5, 
                            timeoutUnit: 'MINUTES'
                        )
                        dockerfileName = dockerfileName?.trim() ? dockerfileName : 'Dockerfile'
                    } catch (org.jenkinsci.plugins.workflow.steps.FlowInterruptedException e) {
                        if (e.getCauses()[0].getClass().getSimpleName() == 'UserInterruption') {
                            echo "Input aborted by user, marking stage as passed."
                            dockerfileName = 'Dockerfile'
                        } else if (e.getCauses()[0].getClass().getSimpleName() == 'TimeoutStepExecution') {
                            echo "Input timed out, using default Dockerfile."
                            dockerfileName = 'Dockerfile'
                        } else {
                            throw e
                        }
                    }

                    echo "Building Docker image using file: ${dockerfileName}"
                    dockerImage = docker.build("${params.DOCKER_HUB_REPO}:latest", "-f ${dockerfileName} .")
                }
            }
        }

        stage('Trivy Scan') {
            steps {
                catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
                    script {
                        sh 'mkdir -p artifacts/trivy'
                        sh '''
                            curl -sSfL -o artifacts/trivy/html.tpl https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/html.tpl
                        '''
                        sh """
                            trivy image --scanners vuln \
                                --severity HIGH,CRITICAL \
                                --format template \
                                --template "@artifacts/trivy/html.tpl" \
                                --timeout 30m \
                                --output artifacts/trivy/report.html ${params.DOCKER_HUB_REPO}:latest
                        """
                    }
                }
            }
        }

        stage('Archive Trivy Report') {
            steps {
                catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
                    archiveArtifacts artifacts: 'artifacts/trivy/report.html', allowEmptyArchive: true
                }
            }
        }

        stage('Push Image to DockerHub') {
            when {
                expression { params.DEPLOY_ENV != 'prod' }
            }
            steps {
                script {
                    def tagsInput = ''
                    try {
                        tagsInput = input message: 'Provide comma-separated tags for the Docker image to push', parameters: [
                            string(defaultValue: 'latest', description: 'Comma-separated tags', name: 'TAGS')
                        ],
                        submitter: '',
                        timeout: 5,
                        timeoutUnit: 'MINUTES'
                        tagsInput = tagsInput?.trim() ? tagsInput : 'latest'
                    } catch (org.jenkinsci.plugins.workflow.steps.FlowInterruptedException e) {
                        if (e.getCauses()[0].getClass().getSimpleName() == 'UserInterruption') {
                            echo "Input aborted by user, marking stage as passed."
                            tagsInput = 'latest'
                        } else if (e.getCauses()[0].getClass().getSimpleName() == 'TimeoutStepExecution') {
                            echo "Input timed out, using default tags."
                            tagsInput = 'latest'
                        } else {
                            throw e
                        }
                    }
                    def tags = tagsInput.tokenize(',').collect { it.trim() }
                    echo "Pushing image with tags: ${tags}"
                    docker.withRegistry('https://registry.hub.docker.com', "${DOCKER_HUB_CREDENTIALS_ID}") {
                        tags.each { tag ->
                            dockerImage.push(tag)
                        }
                    }
                    env.IMAGE_TAGS = tags.join(',')
                }
            }
        }

        stage('Approval for Deployment') {
            when {
                anyOf {
                    branch 'master'
                    branch 'prod'
                }
            }
            steps {
                script {
                    try {
                        input message: "Approve deployment to ${params.DEPLOY_ENV} environment?", submitter: '', timeout: 5, timeoutUnit: 'MINUTES'
                    } catch (org.jenkinsci.plugins.workflow.steps.FlowInterruptedException e) {
                        if (e.getCauses()[0].getClass().getSimpleName() == 'UserInterruption') {
                            echo "Approval aborted by user, marking stage as passed."
                        } else if (e.getCauses()[0].getClass().getSimpleName() == 'TimeoutStepExecution') {
                            echo "Approval timed out, proceeding with deployment."
                        } else {
                            throw e
                        }
                    }
                }
            }
        }

        stage('Create Git Tag') {
            when {
                branch 'master'
            }
            steps {
                withCredentials([usernamePassword(credentialsId: "${GITHUB_CREDENTIALS_ID}", usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN')]) {
                    script {
                        def tagName = ''
                        try {
                            tagName = input message: 'Enter the Git tag name to create', parameters: [string(name: 'TAG_NAME', description: 'Git tag name')],
                            submitter: '',
                            timeout: 5,
                            timeoutUnit: 'MINUTES'
                            tagName = tagName?.trim() ? tagName : ''
                        } catch (org.jenkinsci.plugins.workflow.steps.FlowInterruptedException e) {
                            if (e.getCauses()[0].getClass().getSimpleName() == 'UserInterruption') {
                                echo "Tag creation aborted by user, marking stage as passed."
                                tagName = ''
                            } else if (e.getCauses()[0].getClass().getSimpleName() == 'TimeoutStepExecution') {
                                echo "Tag creation timed out, skipping tag creation."
                                tagName = ''
                            } else {
                                throw e
                            }
                        }
                        if (tagName) {
                            def userName = env.BUILD_USER ?: 'Rajendra.daggubati'
                            def userEmail = "${userName}@gmail.com"
                            echo "Creating Git tag: ${tagName} by user: ${userName} <${userEmail}>"
                            sh """
                                git config user.name "${userName}"
                                git config user.email "${userEmail}"
                                git tag -a ${tagName} -m "Tag created by Jenkins pipeline by ${userName}"
                                git push https://${GIT_USER}:${GIT_TOKEN}@github.com/${env.GITHUB_REPO}.git ${tagName}
                            """
                        } else {
                            echo "No tag name provided, skipping tag creation."
                        }
                    }
                }
            }
        }

        stage('Create Merge Request') {
            when {
                allOf {
                    not {
                        branch 'master'
                    }
                    expression {
                        return !env.CHANGE_ID
                    }
                }
            }
            steps {
                script {
                    def prInputs = ''
                    try {
                        prInputs = input message: 'Provide details for the merge request',
                            parameters: [
                                string(name: 'SOURCE_BRANCH', defaultValue: 'dev/raj/version', description: 'Name of the branch to merge (source)'),
                                string(name: 'PR_TITLE', description: 'Merge request title'),
                                text(name: 'PR_BODY', description: 'Merge request description')
                            ],
                            submitter: '',
                            timeout: 5,
                            timeoutUnit: 'MINUTES'
                    } catch (org.jenkinsci.plugins.workflow.steps.FlowInterruptedException e) {
                        if (e.getCauses()[0].getClass().getSimpleName() == 'UserInterruption') {
                            echo "Merge request input aborted by user, marking stage as passed."
                            prInputs = [
                                'SOURCE_BRANCH': '',
                                'PR_TITLE': '',
                                'PR_BODY': ''
                            ]
                        } else if (e.getCauses()[0].getClass().getSimpleName() == 'TimeoutStepExecution') {
                            echo "Merge request input timed out, skipping merge request creation."
                            prInputs = [
                                'SOURCE_BRANCH': '',
                                'PR_TITLE': '',
                                'PR_BODY': ''
                            ]
                        } else {
                            throw e
                        }
                    }

                    if (prInputs['SOURCE_BRANCH'] == 'master') {
                        error("PR source and target cannot both be 'master'. Please choose a different source branch.")
                    }

                    if (prInputs['SOURCE_BRANCH']) {
                        def jsonPayload = """{
                            "title": "${prInputs['PR_TITLE']}",
                            "head": "${prInputs['SOURCE_BRANCH']}",
                            "base": "master",
                            "body": "${prInputs['PR_BODY']}"
                        }"""

                        writeFile file: 'pr_payload.json', text: jsonPayload

                        withCredentials([string(credentialsId: 'GITHUB_TOKEN', variable: 'GITHUB_TOKEN')]) {
                            sh '''
                                curl -X POST \
                                    -H "Authorization: token $GITHUB_TOKEN" \
                                    -H "Accept: application/vnd.github.v3+json" \
                                    -d @pr_payload.json \
                                    $GITHUB_API_URL/repos/$GITHUB_REPO/pulls
                            '''
                        }
                    } else {
                        echo "No source branch provided, skipping merge request creation."
                    }
                }
            }
        }
    }

    post {
        success {
            echo "Build succeeded!"
            withCredentials([usernamePassword(credentialsId: "${env.EMAIL_CREDENTIALS_ID}", usernameVariable: 'EMAIL_USER', passwordVariable: 'EMAIL_PASS')]) {
                mail to: 'rajendra.daggubati09@gmail.com',
                     subject: "SUCCESS: Job '${env.JOB_NAME}' [${env.BUILD_NUMBER}]",
                     body: "Build succeeded!\n\nSee details: ${env.BUILD_URL}",
                     from: "${EMAIL_USER}"
            }
        }
        failure {
            echo "Build failed!"
            withCredentials([usernamePassword(credentialsId: "${env.EMAIL_CREDENTIALS_ID}", usernameVariable: 'EMAIL_USER', passwordVariable: 'EMAIL_PASS')]) {
                mail to: 'rajendra.daggubati09@gmail.com',
                     subject: "FAILED: Job '${env.JOB_NAME}' [${env.BUILD_NUMBER}]",
                     body: "Build failed!\n\nSee details: ${env.BUILD_URL}",
                     from: "${EMAIL_USER}"
            }
        }
        unstable {
            echo 'Build & Deploy is unstable. Check logs.'
            withCredentials([usernamePassword(credentialsId: "${env.EMAIL_CREDENTIALS_ID}", usernameVariable: 'EMAIL_USER', passwordVariable: 'EMAIL_PASS')]) { 
                mail to: 'rajendra.daggubati09@gmail.com',
                     subject: "FAILED: Job '${env.JOB_NAME}' [${env.BUILD_NUMBER}]",
                     body: "Build failed!\n\nSee details: ${env.BUILD_URL}",
                     from: "${EMAIL_USER}"
            }
        }
        always {
            cleanWs()
            echo 'Workspace cleaned'
        }
    }
}
