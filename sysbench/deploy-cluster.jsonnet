local systemslab = import 'systemslab.libsonnet';
local bash = systemslab.bash;
local upload_artifact = systemslab.upload_artifact;
function()
{
  local config = {
    name: "pingcap-deploy-cluster",  
    tiup_tags: ['pingcap', 'c6g-2xlarge-1'],
    tipd_tags: ['pingcap', 'c6g-2xlarge-2'],
    tikv_1_tags: ['pingcap', 'c6g-2xlarge-3'],
    tidb_1_tags: ['pingcap', 'c6g-2xlarge-4'],  
    tidb_2_tags: ['pingcap', 'c6g-2xlarge-5'],  
    tidb_3_tags: ['pingcap', 'c6g-2xlarge-6'],    
    storage: "/mnt/gp3",
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
    pd_servers: [{ host: "PD_SERVER_IP"}],
    monitoring_servers: [{ host: "PD_SERVER_IP"}],
    grafana_servers: [{ host: "PD_SERVER_IP"}],
    tidb_servers: [{ host: "TIDB_1_SERVER_IP"}, { host: "TIDB_2_SERVER_IP"}, { host: "TIDB_3_SERVER_IP"}],
    tikv_servers: [{ host: "TIKV_1_SERVER_IP"}],   
  },
  metadata: config,
  name: config.name,
  jobs: {
    tiup_control: {
      host: {
        tags: config.tiup_tags,
      },       
      steps: [
        # cleaning up the data also any remaining tidb processes
        bash(        
          |||
            ~/.tiup/bin/tiup cluster destroy systemslab-test -y || true
          |||
        ),        
        systemslab.write_file('topology.yaml', std.manifestYamlDoc(topology, indent_array_in_object=true, quote_keys=false)),
        bash(
          |||
            sed -ie "s/PD_SERVER_IP/${PD_SERVER_ADDR}/g" topology.yaml
            echo "PD SERVER at ${PD_SERVER_ADDR}"
            sed -ie "s/TIDB_1_SERVER_IP/${TIDB_1_SERVER_ADDR}/g" topology.yaml
            sed -ie "s/TIDB_2_SERVER_IP/${TIDB_2_SERVER_ADDR}/g" topology.yaml
            sed -ie "s/TIDB_3_SERVER_IP/${TIDB_3_SERVER_ADDR}/g" topology.yaml
            echo "TIDB SERVER at ${TIDB_SERVER_ADDR} ${TIDB_2_SERVER_ADDR} ${TIDB_3_SERVER_ADDR}"          
            sed -ie "s/TIKV_1_SERVER_IP/${TIKV_1_SERVER_ADDR}/g" topology.yaml
            echo "TIKV SERVERS at ${TIKV_1_SERVER_ADDR} "
            cp ./topology.yaml /tmp/topology.yaml
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
            echo $DB_PASSWORD > /tmp/tidb_password.txt
          |||
        ), 
      ],
    },    
    pd_server: {
      host: {
        tags: config.tipd_tags,         
      },
      steps: [],
    },
    tidb_1_server: {
      host: {
        tags: config.tidb_1_tags,         
      },
      steps : []
    },
    tidb_2_server: {
      host: {
        tags: config.tidb_2_tags,         
      },
      steps : []
    },
    tidb_3_server: {
      host: {
        tags: config.tidb_3_tags,         
      },
      steps : []
    },        
    tikv_1_server: {
      host: {
        tags: config.tikv_1_tags,        
      },
      steps : []
    },              
  }
}