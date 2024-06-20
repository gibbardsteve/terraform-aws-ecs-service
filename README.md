# ECS Service Terraform

## terraform-aws-ecs-service

Terraform to deploy a Fargate service on top of infrastructure provisioned via terraform-aws-ecs-infra

## Infrastructure Change Required

Before provisioning the service the infrastructure must be updated to add a Web Application Firewall (WAF) rule if the servce being aded is restricted by certain IP address ranges.
Applying the IP restriction at the WAF means that users do not go through Cognito authentication to then be rejected because they are trying to gain access from an IP that is not in the allow list.

## ecsTaskExecutionRole

The terraform to create a service requires a role to be created ecsTaskExecutionRole.  This needs to be manually created in AWS console at present (Roles->Create Role->EC2->Attach the AmazonECSTaskExecutionRolePolicy).  The policy that should be applied to the role must match:

```bash
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "",
            "Effect": "Allow",
            "Principal": {
                "Service": "ecs-tasks.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
```

This is a one-off configuration.

## Service Update

A new version of the service can be deployed by specifying the new container version in Terraform and applying the change.

1. Change the container_ver variable to the tagged version to update to (e.g v0.0.3)
2. Ensure the force_deployment variable is set to true
3. Run _terraform validate_, _terraform fmt_ and _terraform plan_ verifying everything is as expected
    - Ensure only the resources that you expect to change are highlighted in the pan
4. Run _terraform apply_
    - The deployment will provision a new task with the specified container version
    - Two tasks will be running during deployment (one with original version and one with specified version)
    - When the specified version is running the original version task will be shutdown
    - The terraform apply waits until only the desired task count is running before returning success

## Terraform Destroy

To run a clean terraform destroy on all resources the S3 bucket created for the application needs to be manually cleared down of any objects prior to running the terraform.  This seems like a reasonable measure as it forces someone to ensure the files are not needed.  If the terraform destroy is run without the S3 bucket being empty that resource will not be deleted and terraform destroy will return an error.
