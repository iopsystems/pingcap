local systemslab = import 'systemslab.libsonnet';
local bash = systemslab.bash;
local upload_artifact = systemslab.upload_artifact;
# example:
#  ec2: 
function(cluster='cluster1', storage='/mnt/gp3')
{
  local config = {
    name: "deploy-cluster-single", 
    client_1_tags: [cluster + '-sysbench-1'],
    tikv_1_tags: [cluster + '-tikv-1'],
    tidb_1_tags: [cluster + '-tidb-1'],
    tipd_1_tags: [cluster + '-tipd-1'],
    monitor_1_tags: [cluster + '-tipd-1'],
    tiup_tags: [cluster + '-sysbench-1'],
    storage: storage,
  },
  local topology = {
    global: {
      user: "systemslab-agent",
      ssh_port: 22,
      deploy_dir: config.storage + "/tidb-deploy",
      data_dir: config.storage + "/tidb-data",
      listen_host: "0.0.0.0",
      arch: "amd64",
    },
    monitoring_servers: [{host: "TIPD_1_IP"}],
    grafana_servers: [{host: "TIPD_1_IP"}],
    pd_servers: [{ host: "TIPD_1_IP"}],
    tidb_servers: [{ host: "TIDB_1_IP"}],
    tikv_servers: [{ host: "TIKV_1_IP"}],   
  },
  metadata: config,
  name: config.name,
  jobs: {
    tiup: {
      host: {
        tags: config.tiup_tags,
      },       
      steps: [
        bash(        
          |||
            ~/.tiup/bin/tiup cluster destroy systemslab-test -y || true
          |||
        ),        
        systemslab.write_file('topology.yaml', std.manifestYamlDoc(topology, indent_array_in_object=true, quote_keys=false)),
        bash(
          |||          
            sed -ie "s/TIDB_1_IP/${TIDB_1_ADDR}/g" topology.yaml
            sed -ie "s/TIKV_1_IP/${TIKV_1_ADDR}/g" topology.yaml
            sed -ie "s/TIPD_1_IP/${TIPD_1_ADDR}/g" topology.yaml
            cp ./topology.yaml ~/topology.yaml
          |||
        ),
        systemslab.upload_artifact('topology.yaml'),
        bash('~/.tiup/bin/tiup cluster check ./topology.yaml --user systemslab-agent | tee tiup_check_log'),
        systemslab.upload_artifact('tiup_check_log'),
        bash('~/.tiup/bin/tiup cluster deploy systemslab-test v8.0.0 ./topology.yaml --user systemslab-agent -y --ignore-config-check | tee tiup_deploy_log'),
        systemslab.upload_artifact('tiup_deploy_log'),
        bash('~/.tiup/bin/tiup cluster start systemslab-test --init -y | tee tiup_start_log'),
        systemslab.upload_artifact('tiup_start_log'),
        bash('~/.tiup/bin/tiup cluster display systemslab-test | tee tiup_display_log'),
        systemslab.upload_artifact('tiup_display_log'),               
        bash(
          |||
            DB_PASSWORD=`cat tiup_start_log | grep -oP "(?<=The new password is: ').*(?=')"`
            echo $DB_PASSWORD > ~/tidb_password.txt
          |||
        ), 
      ],
    },
    tidb_1: {
      host: {
        tags: config.tidb_1_tags,         
      },
      steps : []
    },      
    tikv_1: {
      host: {
        tags: config.tikv_1_tags,        
      },
      steps : []
    },  
    tipd_1: {
      host: {
        tags: config.tipd_1_tags,        
      },
      steps : []
    },                 
  }
}