local systemslab = import 'systemslab.libsonnet';
local bash = systemslab.bash;
local upload_artifact = systemslab.upload_artifact;
local invalidTypeMsg(name, expected, value) = std.format(
  '`%s` had invalid type (expected `%s` but got `%s` instead)',
  [name, expected, std.type(value)]
);

function(cluster='cluster1', threads='16', poolsize='128', tables='1', table_size='100000', time='60', rate='23000')
{
  local config = {
    name: "oltp-sysbench-rpcperf",
    tidb_1_tags: [cluster + '-tidb-1'],
    client_1_tags: [cluster + '-sysbench-1'],   
  },
  local rpcperf_config = {
    general: {
        protocol: 'mysql',
        interval: 1,
        duration: std.parseJson(time),
        metrics_output: 'output.parquet',
        metrics_format: 'parquet',
        metrics_interval: '1s',
        admin: '0.0.0.0:9090',
        initial_seed: '0',
    },
    debug: {
        log_level: 'info',
        log_backup: 'rpc-perf.log.old',
        log_max_size: 1073741824,
    },
    target: {
        endpoints: ['mysql://root:TIDB_PASSWORD@TIDB_1_IP:4000/sbtest'],
    },
    oltp: {
        threads: std.parseJson(threads),
        poolsize: std.parseJson(poolsize),
        connect_timeout: 10000,
        request_timeout: 1000,
        read_buffer_size: 8192,
        write_buffer_size: 8192,
    },
    workload: {
        threads: 1,
        ratelimit: {
            start: std.parseJson(rate),
        },
        oltp: {
            tables: std.parseJson(tables),
            keys: std.parseJson(table_size),
        },
    },
  },
  metadata: config,
  name: config.name,
  jobs: {
    client_1: {
      host: {
        tags: config.client_1_tags,
      },       
      local config_toml = std.manifestTomlEx(rpcperf_config, ''),      
      steps: [
        systemslab.write_file('config.toml', config_toml),
        bash(
          |||
            TIDB_PASSWORD=`cat ~/tidb_password.txt`
            sed -ie "s/TIDB_1_IP/${TIDB_1_ADDR}/g" ./config.toml
            sed -ie "s/TIDB_PASSWORD/${TIDB_PASSWORD}/g" ./config.toml
          |||
        ),
        systemslab.upload_artifact('config.toml'),
        bash(
          |||
            rpc-perf ./config.toml | tee rpc-perf.output
          |||
        ),
        systemslab.upload_artifact('rpc-perf.output'),
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
            RATE=%s
            /home/systemslab-agent/sysbench/src/sysbench --config-file=/home/systemslab-agent/config --report-interval=1 --percentile=99 --time=$SYSBENCH_TIME --rate=$RATE ./oltp_point_select.lua --threads=$SYSBENCH_THREADS --tables=$TABLES --table-size=$TABLE_SIZE --db-ps-mode=auto --rand-type=uniform run | tee sysbench_output.txt
          ||| % [threads, time, tables, table_size, rate]
        ),
        systemslab.upload_artifact('sysbench_output.txt'),        
      ],
    },
    tidb_1: {
      host: {
        tags: config.tidb_1_tags,
      },
      steps: []
    },    
  },
}