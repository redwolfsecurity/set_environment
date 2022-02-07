#!groovy
pipeline {
  agent {
      docker {
          image 'dockerregistry.production.redwolfsecurity.com/redoki_base_ubuntu:latest' 
          args '--user=ubuntu'  // This enforces docker started by Jenknis to use proper "ubuntu" user with all the expected groups (i.e. "docker")
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
        PRODUCTION_AWS_ECR_FQDN = credentials('production_aws_ecr_fqdn')  // e.g. 209512847919.dkr.ecr.us-east-1.amazonaws.com

        // For AWS ECR to work we need to provide AWS key/secret via these 2 environment variables
        AWS_ACCESS_KEY_ID = credentials('production_aws_access_key_id_jenkins_build')
        AWS_SECRET_ACCESS_KEY = credentials('production_aws_secret_access_key_jenkins_build')
        TARBALL_FILENAME = "set_environment-dev.tgz"
        TEMPORARY_DIR = "/tmp"
        TARBALL_FILEPATH = "${TEMPORARY_DIR}/${TARBALL_FILENAME}"
      }
      steps {
        // We need to "npm install" because of aws-sdk dependency (used by cdn_upload.js)
        sh 'npm i'

        // Capture date and build git commit numbers into separate files
        sh 'echo "BUILD_DATE=$(date +%Y%m%d)  # YYYYMMDD" > build_date'
        sh 'echo "BUILD_COMMIT_ID=$(git rev-parse HEAD)"  > build_commit_id'

        // Delete target tmp folder, otherwise copy will result in wrong folder structure (1 level nested deeper)
        sh 'rm -fr ${TEMPORARY_DIR}/set_environment'

        // Before creating tarball: move all files into "set_environment" folder.
        // We do so because while Jenkins buidling the project all the files are located in ugly-looking folder:
        //     /var/jenkins_home/jobs/RedWolfSecurity/jobs/set-environment.ja761g/branches/master/workspace
        sh 'cp -a $(pwd) ${TEMPORARY_DIR}/set_environment'

        // Now we can create tarball which contain just 1 folder 'set_environment'
        // Note on used arguments:
        //       -C  - to tell tar to change directory to ${TEMPORARY_DIR}, so we do not
        //       have nested folders like ${TEMPORARY_DIR}/set_environment inside result tarball)
        //
        //       --exclude-vcs - will help to get rid of all git-related files (no need to publish them)
        //
        //       ${TEMPORARY_DIR}/set_environment.tgz - full path used for the result tarbal otherwize it will be created in
        //                                  current working jenkins directory, like: /var/jenkins_home/jobs/RedWolfSecurity/jobs/set-environment.ja761g/branches/master/workspace
        //
        //      set_environment - last argument is the folder to archive. It does not include full path (like: ${TEMPORARY_DIR}/set_environment)
        //                        because we already specified -C argument.
        //
        
        sh 'tar -C ${TEMPORARY_DIR} --exclude-vcs -czf ${TARBALL_FILENAME} set_environment'

        // Upload tarball to S3 so it is available via URL: https://cdn.redwolfsecurity.com/ff/ff_agent/set_environment.tgz
        sh 'node cdn_upload.js ${TARBALL_FILEPATH} ${PRODUCTION_CONTENT_S3_BUCKET_NAME} ${PRODUCTION_CONTENT_S3_FF_AGENT_PATH} ${PRODUCTION_CONTENT_CDN_DISTRIBUTION_ID}
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
