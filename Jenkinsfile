pipeline {
    agent {
        kubernetes {
            label 'test'
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
    }
    options {
        timeout(time: 90, unit: 'MINUTES')
        timestamps()
        retry(0)
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10', artifactNumToKeepStr: '5'))
    }
    stages {
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
        stage('Dependency Check') {
            when {
                expression { params.DEPLOY_ENV != 'prod' }
            }
            steps {
                script {
                    catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
                        dependencyCheck(
                            additionalArguments: '--scan ./ --format HTML --out artifacts/dependency-check',
                            odcInstallation: 'dpcheck'
                        )
                        archiveArtifacts(
                            artifacts: 'artifacts/dependency-check/dependency-check-report.html',
                            allowEmptyArchive: true
                        )
                    }
                }
            }
        }
        stage('Build Docker Image') {
            steps {
                script {
                    // Ask for Dockerfile name at runtime (optional)
                    def dockerfileName = input(
                        id: 'userInput', message: 'Enter Dockerfile name (leave blank for default)', parameters: [
                            string(defaultValue: '', description: 'Dockerfile name (e.g., Dockerfile.custom)', name: 'DOCKERFILE_NAME')
                        ]
                    )

                    // Use provided file or default to 'Dockerfile'
                    dockerfileName = dockerfileName?.trim() ? dockerfileName : 'Dockerfile'

                    echo "Building Docker image using file: ${dockerfileName}"
                    
                    // Build Docker image with custom Dockerfile
                    dockerImage = docker.build("${DOCKER_HUB_REPO}:latest", "-f ${dockerfileName} .")
                }
            }
        }
        stage('Trivy Scan') {
            steps {
                script {
                    sh 'mkdir -p artifacts/trivy'

                    // Run Trivy and generate HTML report
                    sh """
                        trivy image --severity HIGH,CRITICAL \\
                            --format template \\
                            --template "@contrib/html.tpl" \\
                            --output artifacts/trivy/report.html ${DOCKER_HUB_REPO}:latest
                    """
                }
            }
        }
        stage('Archive Trivy Report') {
            steps {
                archiveArtifacts artifacts: 'artifacts/trivy/report.html', allowEmptyArchive: true
            }
        }
        stage('Push Image to DockerHub') {
            when {
                expression { params.DEPLOY_ENV != 'prod' }
            }
            steps {
                script {
                    def tagsInput = input message: 'Provide comma-separated tags for the Docker image to push', parameters: [string(defaultValue: 'latest', description: 'Comma-separated tags', name: 'TAGS')]
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
                input message: "Approve deployment to ${params.DEPLOY_ENV} environment?"
            }
        }
        stage('Create Git Tag') {
            steps {
                withCredentials([usernamePassword(credentialsId: "${GITHUB_CREDENTIALS_ID}", usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN')]) {
                    script {
                        def tagName = input message: 'Enter the Git tag name to create', parameters: [string(name: 'TAG_NAME', description: 'Git tag name')]
                        def userName = env.BUILD_USER ?: 'Rajendra.daggubati'
                        def userEmail = "${userName}@gmail.com"
                        echo "Creating Git tag: ${tagName} by user: ${userName} <${userEmail}>"
                        sh """
                            git config user.name "${userName}"
                            git config user.email "${userEmail}"
                            git tag -a ${tagName} -m "Tag created by Jenkins pipeline by ${userName}"
                            git push https://${GIT_USER}:${GIT_TOKEN}@github.com/${env.GITHUB_REPO}.git ${tagName}
                        """
                    }
                }
            }
        }
        stage('Create Merge Request') {
            steps {
                script {
                    def prInputs = input message: 'Provide details for the merge request',
                        parameters: [
                            string(name: 'PR_TITLE', description: 'Merge request title'),
                            text(name: 'PR_BODY', description: 'Merge request description')
                        ]

                    withCredentials([string(credentialsId: 'GITHUB_TOKEN', variable: 'GITHUB_TOKEN')]) {
                        def jsonPayload = """{
                            "title": "${prInputs['PR_TITLE']}",
                            "head": "${params.BRANCH_NAME}",
                            "base": "master",
                            "body": "${prInputs['PR_BODY']}"
                        }"""

                        writeFile file: 'pr_payload.json', text: jsonPayload

                        sh """
                            curl -X POST \
                                 -H "Authorization: token ${GITHUB_TOKEN}" \
                                 -H "Accept: application/vnd.github.v3+json" \
                                 -d @pr_payload.json \
                                 ${GITHUB_API_URL}/repos/${GITHUB_REPO}/pulls
                        """
                    }
                }
            }
        }
    }
    post {
        success {
            //slackSend channel: "${env.SLACK_CHANNEL}", color: 'good', message: "Build #${env.BUILD_NUMBER} succeeded for branch ${params.BRANCH_NAME} and environment ${params.DEPLOY_ENV}"
            echo 'Build & Deploy completed successfully!'
        }
        failure {
            //slackSend channel: "${env.SLACK_CHANNEL}", color: 'danger', message: "Build #${env.BUILD_NUMBER} failed for branch ${params.BRANCH_NAME} and environment ${params.DEPLOY_ENV}"
            echo 'Build & Deploy failed. Check logs.'
        }
        unstable {
            //slackSend channel: "${env.SLACK_CHANNEL}", color: 'warning', message: "Build #${env.BUILD_NUMBER} is unstable for branch ${params.BRANCH_NAME} and environment ${params.DEPLOY_ENV}"
            echo 'Build & Deploy is unstable. Check logs.'
        }
        always {
            cleanWs()
            echo 'Workspace cleaned'
        }
    }
}

