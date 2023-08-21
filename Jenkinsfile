#!groovy
pipeline {
  agent {
      docker {
          alwaysPull true
          image '209512847919.dkr.ecr.us-east-1.amazonaws.com/redoki_base_ubuntu_builder:latest'
          registryCredentialsId 'ecr:us-east-1:aws_credentials_jenkins_redwolf'
          registryUrl 'https://209512847919.dkr.ecr.us-east-1.amazonaws.com'
      }
  }

  stages {
    stage('Install') {
      environment {
        FF_CONTENT_URL = credentials('production_content_url')
      }
      steps {
        // For now the 'install' contains the tests.
        sh './install'
      }
    }

    stage('Test') {
      environment {
        FF_CONTENT_URL = credentials('production_content_url')
      }
      steps {
        // PRESERVING DEBUGGING COMMANDS + OUTPUT FOR FUTURE
        // // Debugging
        // sh 'whoami'                                     // ff_agent (with NO environment set - bad)
        // sh 'pwd'
        // sh 'ls -la'
        // sh 'echo ${FF_AGENT_HOME}'                      // empty (with environment set - good)

        // sh 'bash --login -c "whoami"'                   // ff_agent
        // sh 'bash --login -c "pwd"'
        // sh 'bash --login -c "ls -la"'
        // sh 'bash --login -c "echo ${FF_AGENT_HOME}"'    // empty
        // sh 'bash --login -c "echo \${FF_AGENT_HOME}"'   // empty
        // sh 'bash --login -c "echo \\${FF_AGENT_HOME}"'  // this yields: /home/ff_agent/ff_agent

        // Let's run few basic checks by calling is_set_environment_working()
        // sh 'is_set_environment_working'                 // this fails: is_set_environment_working: not found
        sh 'bash --login -c "is_set_environment_working"'

	// Ensure no syntax errors in bash scripts
	sh 'bash -n install'
	sh 'bash -n src/ff_bash_functions'
	sh 'bash -n src/architecture/linux/continue_install.sh'
	sh 'bash -n src/architecture/linux/continue_install.functions.sh'
      }
    }

    stage('Upload to CDN') {
      when {
        anyOf {
          branch 'master'
        }
      }
      environment {
        PRODUCTION_CONTENT_CDN_DISTRIBUTION_ID = credentials('production_content_cdn_distribution_id')
        PRODUCTION_CONTENT_S3_BUCKET_NAME = credentials('production_content_s3_bucket_name')
        PRODUCTION_CONTENT_S3_FF_AGENT_PATH = credentials('production_content_s3_ff_agent_path')

        // AWS ECR related settings
        PRODUCTION_AWS_ECR_FQDN = credentials('production_aws_ecr_fqdn')

        // For AWS ECR to work we need to provide AWS key/secret via these 2 environment variables
        AWS_ACCESS_KEY_ID = credentials('production_aws_access_key_id_jenkins_build')
        AWS_SECRET_ACCESS_KEY = credentials('production_aws_secret_access_key_jenkins_build')
      }
      steps {
        sh './build_tarball'
      }
    }
  }
  post {
    cleanup {
      echo 'One way or another, I have finished'
      deleteDir()
    }
  }
}
