provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

variable "source_repo_name" {
  description = "Source repo name"
  type        = string
}

variable "source_repo_branch" {
  description = "Source repo branch"
  type        = string
}

variable "image_repo_name" {
  description = "Image repo name"
  type        = string
}

resource "aws_codecommit_repository" "source_repo" {
  repository_name = var.source_repo_name
  description     = "Source App Repo"
}

resource "aws_iam_role" "trigger_role" {
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : "sts:AssumeRole",
        "Principal" : {
          "Service" : "events.amazonaws.com"
        },
        "Effect" : "Allow",
        "Sid" : ""
      }
    ]
  })
  path = "/"
}

resource "aws_iam_policy" "trigger_policy" {
  description = "Policy Allow Rule invoke pipeline"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : [
          "codepipeline:StartPipelineExecution"
        ],
        "Effect" : "Allow",
        "Resource" : "${aws_codepipeline.pipeline.arn}"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "trigger-attach" {
  role       = aws_iam_role.trigger_role.name
  policy_arn = aws_iam_policy.trigger_policy.arn
}

resource "aws_cloudwatch_event_rule" "trigger_rule" {
  description = "Trigger the pipeline on change to repo/branch"
  event_pattern = jsonencode({
    "source" : ["aws.codecommit"],
    "detail-type" : ["CodeCommit Repository State Change"],
    "resources" : ["${aws_codecommit_repository.source_repo.arn}"],
    "detail" : {
      "event" : ["referenceCreated", "referenceUpdated"],
      "referenceType" : ["branch"],
      "referenceName" : ["${var.source_repo_branch}"]
    }
  })
  role_arn   = aws_iam_role.trigger_role.arn
  is_enabled = true
}

resource "aws_cloudwatch_event_target" "target_pipeline" {
  rule      = aws_cloudwatch_event_rule.trigger_rule.name
  arn       = aws_codepipeline.pipeline.arn
  role_arn  = aws_iam_role.trigger_role.arn
  target_id = "${var.source_repo_name}-${var.source_repo_branch}-pipeline"
}

resource "aws_ecr_repository" "image_repo" {
  name                 = var.image_repo_name
  image_tag_mutability = "MUTABLE"
}

resource "aws_iam_role" "codebuild_role" {
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : "sts:AssumeRole",
        "Principal" : {
          "Service" : "codebuild.amazonaws.com"
        },
        "Effect" : "Allow"
      }
    ]
  })
  path = "/"
}

resource "aws_iam_policy" "codebuild_policy" {
  description = "Policy to allow codebuild to execute build spec"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "ecr:GetAuthorizationToken"
        ],
        "Effect" : "Allow",
        "Resource" : "*"
      },
      {
        "Action" : [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject"
        ],
        "Effect" : "Allow",
        "Resource" : "${aws_s3_bucket.artifact_bucket.arn}/*"
      },
      {
        "Action" : [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ],
        "Effect" : "Allow",
        "Resource" : "${aws_ecr_repository.image_repo.arn}"
      },
      {
        "Action" : [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:DescribeRepositories",
          "ecr:CreateRepository"
        ],
        "Effect" : "Allow",
        "Resource" : "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/*"
      }
    ]
  })
}



resource "aws_iam_role_policy_attachment" "codebuild-attach" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = aws_iam_policy.codebuild_policy.arn
}

resource "aws_iam_role" "codebuild_terraform_role" {
  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Action" : "sts:AssumeRole",
          "Principal" : {
            "Service" : "codebuild.amazonaws.com"
          },
          "Effect" : "Allow"
        }
      ]
    }
  )
  path = "/"
}

resource "aws_iam_policy" "codebuild_terraform_policy" {
  description = "Policy to allow codebuild to execute build spec"
  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Action" : [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents",
            "ecr:GetAuthorizationToken"
          ],
          "Effect" : "Allow",
          "Resource" : "*"
        },
        {
          "Action" : [
            "cloudformation:ListExports"
          ],
          "Effect" : "Allow",
          "Resource" : "*"
        },
        {
          "Action" : [
            "s3:ListBucket"
          ],
          "Effect" : "Allow",
          "Resource" : "${aws_s3_bucket.tfstate_bucket.arn}"
        },
        {
          "Action" : [
            "s3:GetObject",
            "s3:PutObject"
          ],
          "Effect" : "Allow",
          "Resource" : "${aws_s3_bucket.tfstate_bucket.arn}/*"
        },
        {
          "Action" : [
            "s3:GetObject",
            "s3:GetObjectVersion",
            "s3:PutObject"
          ],
          "Effect" : "Allow",
          "Resource" : "${aws_s3_bucket.artifact_bucket.arn}/*"
        },
        {
          "Action" : [
            "ecr:*",
            "codebuild:*",
            "ecs:*",
            "iam:*",
            "logs:*",
            "elasticloadbalancing:CreateTargetGroup",
            "elasticloadbalancing:DeleteTargetGroup",
            "elasticloadbalancing:CreateRule",
            "elasticloadbalancing:DeleteRule",
            "elasticloadbalancing:DescribeRules", "elasticloadbalancing:DescribeTags",
            "elasticloadbalancing:DescribeTargetHealth",
            "elasticloadbalancing:DescribeTargetGroups",
            "elasticloadbalancing:DescribeTargetGroupAttributes",
            "elasticloadbalancing:ModifyRule",
            "elasticloadbalancing:ModifyTargetGroup",
            "elasticloadbalancing:ModifyTargetGroupAttributes",
            "elasticloadbalancing:SetRulePriorities",
            "elasticloadbalancing:AddTags",
            "elasticloadbalancing:RemoveTags",
            "servicediscovery:CreateService",
            "servicediscovery:GetService",
            "servicediscovery:UpdateService",
            "servicediscovery:DeleteService",
            "servicediscovery:ListTagsForResource",
            "cloudwatch:GetDashboard",
            "cloudwatch:PutDashboard",
            "cloudwatch:PutMetricData",
            "cloudwatch:DeleteDashboards",
            "application-autoscaling:*"
          ],
          "Effect" : "Allow",
          "Resource" : "*"
        }
      ]
    }
  )
}

resource "aws_iam_role_policy_attachment" "codebuild-terraform-attach" {
  role       = aws_iam_role.codebuild_terraform_role.name
  policy_arn = aws_iam_policy.codebuild_terraform_policy.arn
}

resource "aws_iam_role" "codepipeline_role" {
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : "sts:AssumeRole",
        "Principal" : {
          "Service" : "codepipeline.amazonaws.com"
        },
        "Effect" : "Allow"
      }
    ]
  })
  path = "/"
}

resource "aws_iam_policy" "codepipeline_policy" {
  description = "Policy to allow codepipeline to execute"
  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Action" : [
            "s3:GetObject",
            "s3:GetObjectVersion",
            "s3:PutObject",
            "s3:GetBucketVersioning"
          ],
          "Effect" : "Allow",
          "Resource" : "${aws_s3_bucket.artifact_bucket.arn}/*"
        },
        {
          "Action" : [
            "codebuild:StartBuild",
            "codebuild:BatchGetBuilds",
            "cloudformation:*",
            "iam:PassRole",
            "codecommit:CancelUploadArchive",
            "codecommit:GetBranch",
            "codecommit:GetCommit",
            "codecommit:GetUploadArchiveStatus",
            "codecommit:UploadArchive"
          ],
          "Effect" : "Allow",
          "Resource" : "*"
        }
      ]
    }
  )
}

resource "aws_iam_role_policy_attachment" "codepipeline-attach" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = aws_iam_policy.codepipeline_policy.arn
}

resource "aws_s3_bucket" "artifact_bucket" {
  tags = {
    auto-delete = "never"
    auto-stop   = "no"
  }
}

resource "aws_s3_bucket" "tfstate_bucket" {
  tags = {
    auto-delete = "never"
    auto-stop   = "no"
  }
}

resource "aws_codebuild_project" "codebuild" {
  depends_on = [
    aws_codecommit_repository.source_repo,
    aws_ecr_repository.image_repo
  ]
  name         = "codebuild-${var.source_repo_name}-${var.source_repo_branch}"
  service_role = aws_iam_role.codebuild_role.arn
  artifacts {
    type = "CODEPIPELINE"
  }
  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:2.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true
    image_pull_credentials_type = "CODEBUILD"
    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }
    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = data.aws_region.current.name
    }
    environment_variable {
      name  = "IMAGE_REPO_NAME"
      value = var.image_repo_name
    }
  }
  source {
    type      = "CODEPIPELINE"
    buildspec = <<BUILDSPEC
        version: 0.2
        phases:
            pre_build:
                commands:
                - echo Logging in to Amazon ECR...
                - $(aws ecr get-login --region $AWS_DEFAULT_REGION --no-include-email)
                - COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)
                - IMAGE_TAG=$${COMMIT_HASH:=latest}   
                - REPOSITORY_URI=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME         
            build:
                commands:
                - echo Changing to app directory
                - cd $CODEBUILD_SRC_DIR/app
                - echo Build started on `date`
                - echo Building the Docker image...
                - docker build -t $REPOSITORY_URI:latest .
                - docker tag $REPOSITORY_URI:latest $REPOSITORY_URI:$IMAGE_TAG
            post_build:
                commands:
                - echo Build completed on `date`
                - echo Pushing the Docker image...
                - aws ecr describe-repositories --repository-names $IMAGE_REPO_NAME || aws ecr create-repository --repository-name $IMAGE_REPO_NAME
                - docker push $REPOSITORY_URI:latest
                - docker push $REPOSITORY_URI:$IMAGE_TAG
    BUILDSPEC
  }
}

resource "aws_codebuild_project" "codebuild_tfsec" {
  depends_on = [
    aws_codecommit_repository.source_repo
  ]
  name         = "codebuild_tfsec-${var.source_repo_name}-${var.source_repo_branch}"
  service_role = aws_iam_role.codebuild_terraform_role.arn
  artifacts {
    type = "CODEPIPELINE"
  }
  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/tfsec:latest"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = false
    image_pull_credentials_type = "CODEBUILD"
    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = data.aws_region.current.name
    }
  }
  source {
    type      = "CODEPIPELINE"
    buildspec = <<BUILDSPEC
        version: 0.2
        env:
          exported-variables: 
              - BuildID
              - BuildTag
              - Region
              - checks_errors
              - check_high
              - check_warning
              - check_low
        phases:
            pre_build:
                commands:
                - echo "Executing tfsec"
                - mkdir -p $CODEBUILD_SRC_DIR/infra/tfsec/
            build:
                commands:
                - tfsec --version
                - cd $CODEBUILD_SRC_DIR/infra
                - tfsec -s --tfvars-file terraform.tfvars --format junit > tfsec/report.xml
                - num_errors=$(tfsec -s --tfvars-file terraform.tfvars |  grep ERROR | wc -l)
                - num_high=$(tfsec -s --tfvars-file terraform.tfvars |  grep HIGH | wc -l)
                - num_warning=$(tfsec -s --tfvars-file terraform.tfvars |  grep WARNING | wc -l)
                - num_low=$(tfsec -s --tfvars-file terraform.tfvars |  grep LOW | wc -l)
                - export BuildID=$(echo $CODEBUILD_BUILD_ID | cut -d':' -f1)
                - export BuildTag=$(echo $CODEBUILD_BUILD_ID | cut -d':' -f2)
                - export Region=$AWS_DEFAULT_REGION
                - export checks_errors=$num_errors
                - export check_high=$num_high
                - export check_warning=$num_warning
                - export check_low=$num_low
        reports:
            tfsec-reports:
              files: 
                - infra/tfsec/*.xml
              file-format: "JUNITXML"
    BUILDSPEC
  }
}

resource "aws_codebuild_project" "codebuild_tflint" {
  depends_on = [
    aws_codecommit_repository.source_repo
  ]
  name         = "codebuild_tflint-${var.source_repo_name}-${var.source_repo_branch}"
  service_role = aws_iam_role.codebuild_terraform_role.arn
  artifacts {
    type = "CODEPIPELINE"
  }
  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:2.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = false
    image_pull_credentials_type = "CODEBUILD"
  }
  source {
    type      = "CODEPIPELINE"
    buildspec = <<BUILDSPEC
        version: 0.2
        phases:
            pre_build:
                commands:
                - echo "Executing tflint"
                - mkdir -p $CODEBUILD_SRC_DIR/infra/tflint/
                - curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
            build:
                commands:
                - cd "$CODEBUILD_SRC_DIR/infra"
                - tflint --init
                - ls
                - tflint -f junit > "tflint/tflint_report.xml"
                - ls tflint
        reports:
            tflint:
              files:
                - infra/tflint/*.xml
              file-format": "JUNITXML"
    BUILDSPEC
  }
}

resource "aws_codebuild_project" "codebuild_terraform_plan" {
  depends_on = [
    aws_codecommit_repository.source_repo
  ]
  name         = "codebuild_terraform_plan-${var.source_repo_name}-${var.source_repo_branch}"
  service_role = aws_iam_role.codebuild_terraform_role.arn
  artifacts {
    type = "CODEPIPELINE"
  }
  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:2.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = false
    image_pull_credentials_type = "CODEBUILD"
    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }
    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = data.aws_region.current.name
    }
    environment_variable {
      name  = "TF_VERSION"
      value = "1.0.5"
    }
  }
  source {
    type      = "CODEPIPELINE"
    buildspec = <<BUILDSPEC
        version: 0.2
        phases:
            install:
                commands:
                - "cd /usr/bin"
                - "curl -s -qL -o terraform.zip https://releases.hashicorp.com/terraform/$${TF_VERSION}/terraform_$${TF_VERSION}_linux_amd64.zip"
                - "unzip -o terraform.zip"
            build:
                commands:
                - echo Terraform deployment started on `date`
                - cd "$CODEBUILD_SRC_DIR/infra"
                - echo "terraform" { > backend.tf
                - echo "   backend \"s3\" {} " >> backend.tf
                - echo "}" >> backend.tf
                - terraform init -input=false --backend-config="bucket=${aws_s3_bucket.tfstate_bucket.id}" --backend-config="key=${var.source_repo_name}-${var.source_repo_branch}.tfsate" --backend-config="region=${data.aws_region.current.name}"
                - terraform plan -input=false -var-file=./terraform.tfvars
            post_build:
                commands:
                - echo "Terraform completed on `date`"
    BUILDSPEC
  }
}

resource "aws_codebuild_project" "codebuild_terraform" {
  depends_on = [
    aws_codecommit_repository.source_repo
  ]
  name         = "codebuild_terraform-${var.source_repo_name}-${var.source_repo_branch}"
  service_role = aws_iam_role.codebuild_terraform_role.arn
  artifacts {
    type = "CODEPIPELINE"
  }
  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:2.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = false
    image_pull_credentials_type = "CODEBUILD"
    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }
    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = data.aws_region.current.name
    }
    environment_variable {
      name  = "TF_VERSION"
      value = "1.0.5"
    }
  }
  source {
    type      = "CODEPIPELINE"
    buildspec = <<BUILDSPEC
        version: 0.2
        phases:
            install:
                commands:
                - "cd /usr/bin"
                - "curl -s -qL -o terraform.zip https://releases.hashicorp.com/terraform/$${TF_VERSION}/terraform_$${TF_VERSION}_linux_amd64.zip"
                - "unzip -o terraform.zip"
            build:
                commands:
                - echo Terraform deployment started on `date`
                - cd "$CODEBUILD_SRC_DIR/infra"
                - echo "terraform" { > backend.tf
                - echo "   backend \"s3\" {} " >> backend.tf
                - echo "}" >> backend.tf
                - terraform init -input=false --backend-config="bucket=${aws_s3_bucket.tfstate_bucket.id}" --backend-config="key=${var.source_repo_name}-${var.source_repo_branch}.tfsate" --backend-config="region=${data.aws_region.current.name}"
                - terraform apply -input=false -var-file=./terraform.tfvars -auto-approve
            post_build:
                commands:
                - echo "Terraform completed on `date`"
    BUILDSPEC
  }
}

resource "aws_codepipeline" "pipeline" {
  depends_on = [
    aws_codebuild_project.codebuild,
    aws_codebuild_project.codebuild_terraform,
    aws_codebuild_project.codebuild_terraform_plan,
    aws_codebuild_project.codebuild_tflint,
    aws_codebuild_project.codebuild_tfsec
  ]
  name     = "${var.source_repo_name}-${var.source_repo_branch}-Pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn
  artifact_store {
    location = aws_s3_bucket.artifact_bucket.bucket
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      version          = "1"
      provider         = "CodeCommit"
      output_artifacts = ["SourceOutput"]
      run_order        = 1
      configuration = {
        RepositoryName       = var.source_repo_name
        BranchName           = var.source_repo_branch
        PollForSourceChanges = "false"
      }
    }
  }
  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      version          = "1"
      provider         = "CodeBuild"
      input_artifacts  = ["SourceOutput"]
      output_artifacts = ["BuildOutput"]
      run_order        = 1
      configuration = {
        ProjectName = aws_codebuild_project.codebuild.id
      }
    }
  }
  stage {
    name = "tf-sec-lint"
    action {
      name = "tf-sec"
      category        = "Build"
      owner           = "AWS"
      version         = "1"
      provider        = "CodeBuild"
      input_artifacts = ["SourceOutput"]
      run_order       = 1
      namespace = "TFSEC"
      configuration = {
        ProjectName = aws_codebuild_project.codebuild_tfsec.id
      }
    }
    action {
      name = "tf-lint"
      category        = "Build"
      owner           = "AWS"
      version         = "1"
      provider        = "CodeBuild"
      input_artifacts = ["SourceOutput"]
      run_order       = 1
      configuration = {
        ProjectName = aws_codebuild_project.codebuild_tflint.id
      }
    }
  }
  stage {
    name = "TerraformActions"
    action {
      name = "approval-tfsec"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"
      run_order = 1
      configuration = {
        CustomData = "tfsec errors found: #{TFSEC.checks_errors}, tfsec high found: #{TFSEC.check_high}, tfsec warning found: #{TFSEC.check_warning}, tfsec low found: #{TFSEC.check_low}"
        ExternalEntityLink = "https://#{TFSEC.Region}.console.aws.amazon.com/codesuite/codebuild/${data.aws_caller_identity.current.account_id}/projects/#{TFSEC.BuildID}/build/#{TFSEC.BuildID}%3A#{TFSEC.BuildTag}/reports?region=#{TFSEC.Region}"
      }
    }
    action {
      name            = "TerraformPlan"
      category        = "Build"
      owner           = "AWS"
      version         = "1"
      provider        = "CodeBuild"
      input_artifacts = ["SourceOutput"]
      run_order       = 2
      configuration = {
        ProjectName = aws_codebuild_project.codebuild_terraform_plan.id
      }
    }
    action {
      name = "approval-terraform-plan"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"
      run_order = 3
    }
    action {
      name            = "TerraformApply"
      category        = "Build"
      owner           = "AWS"
      version         = "1"
      provider        = "CodeBuild"
      input_artifacts = ["SourceOutput"]
      run_order       = 4
      configuration = {
        ProjectName = aws_codebuild_project.codebuild_terraform.id
      }
  }
  }
}