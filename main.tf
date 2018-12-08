terraform {
  required_version = "0.11.7"
  backend "s3" {
    bucket = "fh-terraform-states"
    key    = "aws-codepipeline-test"
    region = "eu-central-1"
  }
}

provider "aws" {
  region  = "eu-central-1"
}

variable "github_token" {}

resource "aws_s3_bucket" "foo" {
  bucket = "fh-codepipeline-artifacts"
  acl    = "private"
}

resource "aws_iam_role" "foo" {
  name = "test-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codepipeline.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "codepipeline_policy"
  role = "${aws_iam_role.foo.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect":"Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetBucketVersioning"
      ],
      "Resource": [
        "${aws_s3_bucket.foo.arn}",
        "${aws_s3_bucket.foo.arn}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "codebuild:BatchGetBuilds",
        "codebuild:StartBuild"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

data "aws_kms_alias" "s3kmskey" {
  name = "alias/configuration"
}

resource "aws_codepipeline" "foo" {
  name     = "tf-test-pipeline"
  role_arn = "${aws_iam_role.foo.arn}"

  artifact_store {
    location = "${aws_s3_bucket.foo.bucket}"
    type     = "S3"

    encryption_key {
      id   = "${data.aws_kms_alias.s3kmskey.arn}"
      type = "KMS"
    }
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["test"]

      configuration {
        Owner  = "FaHeymann"
        Repo   = "aws-codepipeline-test"
        Branch = "master"
        OAuthToken = "${var.github_token}"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name            = "Build"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["test"]
      version         = "1"

      configuration {
        ProjectName = "test"
      }
    }
  }
}