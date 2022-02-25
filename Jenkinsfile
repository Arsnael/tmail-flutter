pipeline {
  agent any

  options {
    // Configure an overall timeout for the build.
    timeout(time: 1, unit: 'HOURS')
    disableConcurrentBuilds()
  }

  stages {
    stage('Deliver web Docker image') {
      when {
        anyOf {
          buildingTag()
        }
      }
      steps {
        script {
          env.DOCKER_TAG = 'alpha'
          if (env.TAG_NAME) {
            env.DOCKER_TAG = env.TAG_NAME
          }

          echo "Docker tag: ${env.DOCKER_TAG}"

          // Build image
          sh "docker build -t rcordier/tmail-web:${env.DOCKER_TAG} ."

          def webImage = docker.image "rcordier/tmail-web:${env.DOCKER_TAG}"
          docker.withRegistry('', 'dockerHub') {
            webImage.push()
          }
        }
      }
    }
  }
}