# Create EC2 Instances
Update `./aws/agents.tf` to add and remove EC2 instances. For example:
```
    {
      type = "c6g.2xlarge",
      count = 6
      groups = ["pingcap"]
      tags = ["pingcap-c6g-2xlarge"]
      ami   = "ami-0a24e6e101933d294"
      root_volume_type = "gp3"
      root_volume_size = "300"
      autoshutdown = false
    },
```
creates 6 new EC2 instances.

Run `terraform apply`  in the `aws` directory to create the instances, then run `ansible playbook.yaml` to install software and set the systems.

# Run Sysbench Experiment
## Deploy the cluster
`./sysbench/deploy-cluster.jsonnet` is the Systemslab spec to deploy a Pingcap cluster. Here are examples:
```
systemslab submit --wait ./sysbench/deploy-cluster.jsonnet -p ec2='c6g-2xlarge' -p storage='/mnt/gp3'
systemslab submit --wait ./sysbench/deploy-cluster.jsonnet -p ec2='c6gd-2xlarge' -p storage='/mnt/localssd-1'
```