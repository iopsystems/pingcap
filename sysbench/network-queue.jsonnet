local systemslab = import 'systemslab.libsonnet';
local bash = systemslab.bash;
local upload_artifact = systemslab.upload_artifact;
function(ec2='c6g-2xlarge', sysbench_threads="16", tikv_network_queue="8", tables="1", table_size="100000", time="120")
{
  local config = {
    name: "pingcap-network-queue",  
    client_1_tags: ['pingcap-' + ec2, ec2 + '-1'],  
    tikv_1_tags: ['pingcap-' + ec2, ec2 + '-3'],
    tidb_1_tags: ['pingcap-' + ec2, ec2 + '-4'],  
    tidb_2_tags: ['pingcap-' + ec2, ec2 + '-5'],  
    tidb_3_tags: ['pingcap-' + ec2, ec2 + '-6'],        
    sysbench_threads: std.parseJson(sysbench_threads),
    tikv_network_queue: std.parseJson(tikv_network_queue),  
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
        systemslab.barrier('tikv-network-queue'),
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
            sysbench --report-interval=1 --percentile=99 --time=$SYSBENCH_TIME --config-file=/home/systemslab-agent/config ./oltp_point_select.lua --threads=$SYSBENCH_THREADS --tables=$TABLES --table-size=$TABLE_SIZE --db-ps-mode=auto --rand-type=uniform run | tee sysbench_output.txt
          ||| % [config.sysbench_threads, time, tables, table_size]
        ),
        systemslab.upload_artifact('sysbench_output.txt'),
        #systemslab.upload_artifact('sysbench_start'),
        #systemslab.upload_artifact('sysbench_end'),
      ],
    },        
    tikv_1_server: {
      host: {
        tags: config.tikv_1_tags,        
      },
      steps : 
        if config.tikv_network_queue == 1 then [
          bash(        
            |||
              sudo ethtool -L ens5 combined 1
              TIKV_PID=`pgrep tikv`              
              sudo taskset -apc 1-7 $TIKV_PID
            |||
          ),          
          systemslab.barrier('tikv-network-queue'),
        ] else if config.tikv_network_queue == 2 then [
          bash(        
            |||            
              sudo ethtool -L ens5 combined 2
              TIKV_PID=`pgrep tikv`              
              sudo taskset -apc 2-7 $TIKV_PID
            |||
          ),
          systemslab.barrier('tikv-network-queue'),
        ] else if config.tikv_network_queue == 4 then [
          bash(        
            |||            
              sudo ethtool -L ens5 combined 4
              TIKV_PID=`pgrep tikv`              
              sudo taskset -apc 4-7 $TIKV_PID
            |||
          ),
          systemslab.barrier('tikv-network-queue'),
        ] 
        else if config.tikv_network_queue == 8 then [
          bash(        
            |||            
              sudo ethtool -L ens5 combined 8
              TIKV_PID=`pgrep tikv`              
              sudo taskset -apc 0-7 $TIKV_PID
            |||
          ),
          systemslab.barrier('tikv-network-queue'),
        ] else [],
    },              
  },
}