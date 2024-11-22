local systemslab = import 'systemslab.libsonnet';
local bash = systemslab.bash;
local upload_artifact = systemslab.upload_artifact;
function(cluster='cluster1', sysbench_threads="64", tidb_network_queue="8", tables="1", table_size="100000", time="10")
{
  local config = {
    name: "tidb-network-queue",
    client_1_tags: [cluster + '-sysbench-1'],
    tikv_1_tags: [cluster + '-tikv-1'],
    tidb_1_tags: [cluster + '-tidb-1'],
    tipd_1_tags: [cluster + '-tipd-1'],      
    sysbench_threads: std.parseJson(sysbench_threads),
    tidb_network_queue: std.parseJson(tidb_network_queue),  
  },
  metadata: config,
  name: config.name,
  jobs: {
    client_1_tags: {
      host: {
        tags: config.client_1_tags,
      },       
      steps: [
        # wait for the TIKV network queue setting
        systemslab.barrier('tidb-network-queue'),
        systemslab.write_file('oltp_common.lua', importstr './oltp_common.lua'),
        systemslab.write_file('oltp_point_select.lua', importstr './oltp_point_select.lua'),
        # run sysbench
        bash(        
          |||
            sleep 2
            SYSBENCH_THREADS=%s
            SYSBENCH_TIME=%s
            TABLES=%s
            TABLE_SIZE=%s            
            ~/sysbench-with-queue --config-file=/home/systemslab-agent/config --report-interval=1 --percentile=99 --histogram=on --time=$SYSBENCH_TIME  ./oltp_point_select.lua --threads=$SYSBENCH_THREADS --tables=$TABLES --table-size=$TABLE_SIZE --db-ps-mode=auto --rand-type=uniform run | tee sysbench_output.txt
          ||| % [config.sysbench_threads, time, tables, table_size]
        ),
        systemslab.upload_artifact('sysbench_output.txt'),
        systemslab.barrier('end'),
        #systemslab.upload_artifact('sysbench_start'),
        #systemslab.upload_artifact('sysbench_end'),
      ],
    },        
    tidb_1_server: {
      host: {
        tags: config.tidb_1_tags,        
      },
      steps : 
        if config.tidb_network_queue == 1 then [
          bash(        
            |||
              sudo ethtool -L ens5 combined 1
            |||
          ),          
          systemslab.barrier('tidb-network-queue'),
          systemslab.barrier('end'),
        ] else if config.tidb_network_queue == 2 then [
          bash(        
            |||            
              sudo ethtool -L ens5 combined 2
            |||
          ),
          systemslab.barrier('tidb-network-queue'),
          systemslab.barrier('end'),
        ] else if config.tidb_network_queue == 4 then [
          bash(        
            |||            
              sudo ethtool -L ens5 combined 4
            |||
          ),
          systemslab.barrier('tidb-network-queue'),
          systemslab.barrier('end'),
        ] 
        else if config.tidb_network_queue == 8 then [
          bash(        
            |||            
              sudo ethtool -L ens5 combined 8
            |||
          ),
          systemslab.barrier('tidb-network-queue'),
          systemslab.barrier('end'),
        ] else [],
    },              
  },
}