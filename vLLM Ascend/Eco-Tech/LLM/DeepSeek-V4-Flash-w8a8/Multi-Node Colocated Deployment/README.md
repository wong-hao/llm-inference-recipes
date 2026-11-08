通用 vLLM 模型部署与重启教程
一、先选方案
场景	用哪套
只重启服务进程，不动容器配置（镜像/挂载/设备/shm-size 都不变）	方案 A：容器内重启
换镜像、改挂载、改设备、改 shm-size、容器坏了、要打补丁	方案 B：重建容器
方案 A 不能应用 docker_start.sh 的改动；改了启动脚本必须走方案 B。

二、方案 A：容器内重启（轻量，不重建容器）
适用：只重启 vLLM 服务，容器配置无变化。

每台执行：
bash
# 进容器
docker exec -it <容器名> bash

# 停掉 vLLM 服务（按你 start.sh 的实际启动方式选一个）
pkill -f vllm
# 或
pkill -f <模型进程关键字>

exit
或者直接重启容器（等价于重启容器内进程，仍不应用 docker_start.sh 改动）：

bash
docker restart <容器名>
重启后按下面「启动服务 / 验证」执行。

三、方案 B：重建容器（换镜像、改挂载、改设备、改 shm-size、容器坏了、要打补丁）
第 1 步：所有节点停并删容器
每台执行：

bash
# 停
docker stop <容器名>

# 删
docker rm <容器名>

# 确认 NPU/GPU 释放
sleep 5
npu-smi info        # NVIDIA 用 nvidia-smi

# 确认容器没了
docker ps -a | grep <容器名>
所有节点都做。

第 2 步：所有节点改 docker_start.sh（如需）
bash
vi /data/script/docker_start.sh
常见需要改的内容：

镜像名

容器名

挂载目录

设备映射（NPU/GPU）

--shm-size

端口映射

环境变量

第 3 步：所有节点重建容器
每台执行：

bash
cd /data/script
bash docker_start.sh

# 确认容器起来了
docker ps | grep <容器名>
第 4 步：所有节点容器内打补丁（如需要）
每台机器都要执行，将宿主机的补丁复制进容器并应用：

bash
# 1. 进入容器
docker exec -it <容器名> bash

# 2. 进入容器内的脚本目录，拷贝补丁到 vLLM 工作区
cd /data/script/
cp <补丁文件>.patch /vllm-workspace/<项目目录>/
如cp feat_engram.patch /vllm-workspace/vllm-ascend/

# 3. 进入工作区，应用补丁
cd /vllm-workspace/<项目目录>/
git apply <补丁文件>.patch

如
cd /vllm-workspace/vllm-ascend/
git apply feat_engram.patch

# 4. 退出容器
exit
注：如果 git apply 报错提示文件已存在或冲突，说明之前的残留没删干净，需检查容器是否被完整删除重建；或者尝试：

bash
git apply --reject <补丁文件>.patch
查看冲突点。

四、启动服务（A、B 通用）
顺序：node0 先，node1~N 尽快跟上。

node0（主节点）
bash
docker exec d9bb226f8362 bash -c "cd /data/script && bash start.sh"
等 5~10 秒看日志：

bash
docker exec <容器名> tail -f /data/script/<日志文件>.log
node1 ~ nodeN（从节点）
五、验证（A、B 通用）
bash
docker exec <容器名> tail -f /data/script/<日志文件>.log
检查模型列表：

bash
curl http://<主机IP>:<端口>/v1/models
例如：

bash
curl http://202.115.138.84:8026/v1/models

测试步骤：
三、第一次执行步骤
1. 确认容器在跑
bash
docker ps | grep vllm-ascend
拿到容器 ID（示例 f71185cac1b8）。

2. 确认服务端正常
bash
# 看 vllm 服务日志
tail -f /root/script/deepseek_v4.1.log

# 或者直接探活
curl -s http://202.115.138.86:8026/v1/models
返回模型列表 = 服务就绪。

3. 确认 NPU 空闲
bash
npu-smi info
空闲特征：AICore 接近 0，只有 VLLMWorker_DP 进程占着显存（预分配的 KV cache，正常）。

4. 后台启动压测（关键）
bash
nohup docker exec f71185cac1b8 bash -c "cd /data/script && bash vllm_bench.sh 2>&1" > vllm_bench_result.log 2>&1 &
拆解：

片段	作用
nohup	忽略 SIGHUP，SSH 断开也不中断
docker exec ... bash -c "..."	在容器里执行脚本
> vllm_bench_result.log 2>&1	stdout + stderr 写入宿主机当前目录日志
&	丢后台
执行后返回类似 [1] 609656，即后台任务号 + PID。

5. 确认真的在跑
bash
# 后台任务状态，应为「运行中」
jobs

# 看日志开头，出现 Namespace(...) 和 Starting main benchmark run... 即为启动成功
tail -f vllm_bench_result.log
注意：tail -f 时按 Ctrl+C 只退出查看，不会杀掉后台压测进程。

6. 盯 NPU 占用（另开终端）
bash
watch -n 1 "npu-smi info | grep -E '910B3|Chip'"
AICore 从 0 冲上去（60%+）说明请求真的打到卡上了。

7. 等待跑完
判断完成的标志：日志末尾出现汇总表

text
============ Serving Benchmark Result ============
Successful requests: ...
Benchmark duration (s): ...
Request throughput (req/s): ...
Output token throughput (tok/s): ...
TTFT (ms): ...
TPOT (ms): ...
...
==================================================
8. 提取结果
bash
# 完整结果
tail -n 40 vllm_bench_result.log

# 只看关键指标
grep -iE "ttft|tpot|itl|e2el|throughput|Successful|duration" vllm_bench_result.log
关键指标速查：

指标	含义
TTFT	首 token 延迟
TPOT	每输出 token 耗时
ITL	token 间延迟
E2EL	端到端延迟
Request throughput	请求吞吐（req/s）
Output token throughput	输出 token 吞吐（tok/s）
四、重新执行第二次的步骤
核心：清理上一次的残留，避免结果覆盖/进程冲突。

1. 确认上一次跑完、进程已退出
bash
jobs            # 应显示 Done，而不是 运行中

# 宿主机查
ps -ef | grep -E "vllm_bench|docker exec" | grep -v grep

# 容器内查
docker exec f71185cac1b8 ps -ef | grep vllm | grep -v grep
如果有残留（比如上次被 Ctrl+C 中断了），清掉：

bash
# 容器内清 vllm bench 客户端进程
docker exec f71185cac1b8 pkill -f "vllm bench"
2. 备份上一次结果（重要）
日志文件会被覆盖，想留旧数据先改名：

bash
cd /root/script
mv vllm_bench_result.log vllm_bench_result_$(date +%Y%m%d_%H%M%S).log
或者第二次直接用追加模式 >>（但不推荐，混在一起不好看）。

3. 确认服务仍然正常
bash
curl -s http://202.115.138.86:8026/v1/models
4. 确认 NPU 回到空闲（上一次跑完 AICore 应回落）
bash
npu-smi info
5. 重新启动压测
命令和第一次完全一样：

bash
cd /root/script
nohup docker exec f71185cac1b8 bash -c "cd /data/script && bash vllm_bench.sh 2>&1" > vllm_bench_result.log 2>&1 &
6. 重复第一次的「确认 → 盯 NPU → 等结果 → 提取」流程
bash
jobs
tail -f vllm_bench_result.log
# 另开终端
watch -n 1 "npu-smi info | grep -E '910B3|Chip'"
# 跑完后
grep -iE "ttft|tpot|itl|e2el|throughput|Successful" vllm_bench_result.log
五、常见坑与排查
坑 1：宿主机直接跑 bash vllm_bench.sh 报 vllm: 未找到命令
原因：宿主机没装 vllm。必须 docker exec 进容器跑。

坑 2：./vllm_bench.sh 报 Permission denied
原因：脚本没有可执行权限。

bash
chmod +x vllm_bench.sh     # 或者用 bash vllm_bench.sh 绕过
坑 3：命令敲完卡在 > 提示符
原因：引号没闭合，shell 在等补全。

bash
Ctrl+C   # 取消，重新敲，注意末尾的双引号
坑 4：日志一直空白 / 没有 Namespace(...)
排查：

bash
# 看进程在不在
ps -ef | grep 609656
docker exec f71185cac1b8 ps -ef | grep vllm

# 手动前台跑一次看报错
docker exec f71185cac1b8 bash -c "cd /data/script && bash vllm_bench.sh"
常见原因：host/port 写错、tokenizer 路径不存在、服务端没起来。

坑 5：vllm bench serve 连不上服务
bash
# 在容器里测连通性
docker exec f71185cac1b8 curl -s http://202.115.138.86:8026/v1/models
不通就检查服务端 IP/端口、防火墙。

坑 6：AICore 一直是 0
说明请求没真正打到卡上。检查：

脚本里的 --host / --port 是否指向正在跑的那台

服务端日志 /root/script/deepseek_v4.1.log 有没有收到 POST /v1/chat/completions

坑 7：直接关 SSH 终端
前台跑的命令会随会话被杀。必须 nohup ... & 或 tmux / screen。

坑 8：日志写在容器里而不是宿主机
如果用 docker exec ... bash -c "... | tee xxx.log"，tee 在容器内执行，日志落容器。要在宿主机：

bash
# 方式一：管道放到宿主机（tee 在宿主机执行）
docker exec f71185cac1b8 bash -c "cd /data/script && bash vllm_bench.sh 2>&1" | tee vllm_bench_result.log

# 方式二：跑完从容器拷出来
docker exec f71185cac1b8 bash -c "cd /data/script && bash vllm_bench.sh 2>&1 | tee /data/script/vllm_bench_result.log"
docker cp f71185cac1b8:/data/script/vllm_bench_result.log ./vllm_bench_result.log
六、一页速查
第一次：

bash
cd /root/script
docker ps | grep vllm-ascend                              # 拿容器 ID
curl -s http://202.115.138.86:8026/v1/models              # 服务探活
npu-smi info                                              # NPU 空闲确认
nohup docker exec <容器ID> bash -c "cd /data/script && bash vllm_bench.sh 2>&1" > vllm_bench_result.log 2>&1 &
jobs                                                      # 确认运行中
tail -f vllm_bench_result.log                             # 看进度
第二次：

bash
cd /root/script
jobs                                                      # 上次应 Done
docker exec <容器ID> pkill -f "vllm bench"                # 清残留（如有）
mv vllm_bench_result.log vllm_bench_result_$(date +%Y%m%d_%H%M%S).log   # 备份
curl -s http://202.115.138.86:8026/v1/models              # 服务探活
nohup docker exec <容器ID> bash -c "cd /data/script && bash vllm_bench.sh 2>&1" > vllm_bench_result.log 2>&1 &
看结果：

bash
grep -iE "ttft|tpot|itl|e2el|throughput|Successful|duration" vllm_bench_result.log