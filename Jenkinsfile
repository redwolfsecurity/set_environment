#!groovy
pipeline {
  agent {
      docker {
          image 'dockerregistry.production.redwolfsecurity.com/redoki_base_ubuntu:latest' 
          args '--user=ff_agent'  // This enforces docker started by Jenknis to use proper "ubuntu" user with all the expected groups (i.e. "docker")
      }
  }

  tools {nodejs "node"}
  
  stages {
    stage('Upload to CDN') {
      when {
        anyOf {
          branch 'master';
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
