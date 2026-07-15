#!/bin/bash
# =====================================================
# 钉钉机器人 Webhook 地址（请替换为自己的）
# =====================================================
WEBHOOK_URL="https://oapi.dingtalk.com/robot/send?access_token=$1"

# 检查依赖命令
for cmd in curl bc ss df free uptime ip; do
    if ! command -v $cmd &>/dev/null; then
        echo "错误：未找到命令 $cmd，请先安装。"
        exit 1
    fi
done

# ---------- 收集信息 ----------
HOSTNAME=$(hostname)
IP=$(ip route get 1 2>/dev/null | awk '{print $NF;exit}')
[ -z "$IP" ] && IP="无法获取"

CURRENT_TIME=$(date "+%Y-%m-%d %H:%M:%S")
UPTIME=$(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk '{print $1,$2,$3,$4}' | sed 's/,//g')

# CPU 负载
LOAD=$(uptime | awk -F'load average:' '{print $2}' | sed 's/^ //')

# 内存使用（单位 MB）
MEM_TOTAL=$(free -m | awk '/Mem:/{print $2}')
MEM_USED=$(free -m | awk '/Mem:/{print $3}')
MEM_FREE=$(free -m | awk '/Mem:/{print $4}')
MEM_AVAIL=$(free -m | awk '/Mem:/{print $7}')
if [ "$MEM_TOTAL" -gt 0 ]; then
    MEM_USAGE_PERCENT=$(echo "scale=1; $MEM_USED*100/$MEM_TOTAL" | bc)
else
    MEM_USAGE_PERCENT="N/A"
fi

# 交换分区
SWAP_TOTAL=$(free -m | awk '/Swap:/{print $2}')
SWAP_USED=$(free -m | awk '/Swap:/{print $3}')
SWAP_USAGE_PERCENT="0"
if [ "$SWAP_TOTAL" -gt 0 ]; then
    SWAP_USAGE_PERCENT=$(echo "scale=1; $SWAP_USED*100/$SWAP_TOTAL" | bc)
fi

# 磁盘使用（根分区及所有分区）
ROOT_USAGE=$(df -h / | awk 'NR==2{print $5}' | sed 's/%//')
ROOT_USED=$(df -h / | awk 'NR==2{print $3}')
ROOT_TOTAL=$(df -h / | awk 'NR==2{print $2}')

# 所有分区的信息（仅显示使用率 > 0 的）
ALL_DISK=$(df -h | awk 'NR>1 && $5+0 > 0 {printf "%-20s %-6s %-8s %-8s\n", $6, $5, $3, $2}' | column -t)

# 网络连接统计
ESTABLISHED=$(ss -tunap 2>/dev/null | grep -c ESTAB)
TIME_WAIT=$(ss -tunap 2>/dev/null | grep -c TIME-WAIT)
CLOSE_WAIT=$(ss -tunap 2>/dev/null | grep -c CLOSE-WAIT)
SYN_RECV=$(ss -tunap 2>/dev/null | grep -c SYN-RECV)
TOTAL_CONNS=$(ss -s 2>/dev/null | grep -E "^TCP" | awk '{print $2}' | head -1)
[ -z "$TOTAL_CONNS" ] && TOTAL_CONNS="未知"

# 进程数
PROCESS_COUNT=$(ps aux --no-heading 2>/dev/null | wc -l)

# ---------- 构建 Markdown 消息 ----------
MESSAGE="## 🔍 服务器巡检报告\n"
MESSAGE+="**主机名**: $HOSTNAME\n"
MESSAGE+="**IP地址**: $IP\n"
MESSAGE+="**巡检时间**: $CURRENT_TIME\n"
MESSAGE+="**运行时长**: $UPTIME\n"
MESSAGE+="\n### 📊 CPU 负载\n"
MESSAGE+="负载 (1/5/15分钟): $LOAD\n"
MESSAGE+="\n### 💾 内存使用\n"
MESSAGE+="总内存: ${MEM_TOTAL}MB, 已用: ${MEM_USED}MB, 空闲: ${MEM_FREE}MB\n"
MESSAGE+="可用: ${MEM_AVAIL}MB, 使用率: ${MEM_USAGE_PERCENT}%\n"
if [ "$SWAP_TOTAL" -gt 0 ]; then
    MESSAGE+="交换分区: 总 ${SWAP_TOTAL}MB, 已用 ${SWAP_USED}MB, 使用率 ${SWAP_USAGE_PERCENT}%\n"
else
    MESSAGE+="交换分区: 无\n"
fi
MESSAGE+="\n### 💽 磁盘使用\n"
MESSAGE+="根分区: 已用 $ROOT_USED / 总 $ROOT_TOTAL, 使用率 ${ROOT_USAGE}%\n"
MESSAGE+="\n**所有分区:**\n\`\`\`\n$ALL_DISK\n\`\`\`\n"

# 磁盘告警
if [ "$ROOT_USAGE" -gt 85 ] 2>/dev/null; then
    MESSAGE+="\n⚠️ **告警**: 根分区磁盘使用率超过 85%！\n"
fi

MESSAGE+="\n### 🌐 网络连接\n"
MESSAGE+="当前TCP连接数: $TOTAL_CONNS\n"
MESSAGE+="ESTABLISHED: $ESTABLISHED, TIME_WAIT: $TIME_WAIT\n"
MESSAGE+="CLOSE_WAIT: $CLOSE_WAIT, SYN_RECV: $SYN_RECV\n"
MESSAGE+="\n### 📌 进程数\n"
MESSAGE+="当前进程总数: $PROCESS_COUNT\n"

# ---------- 发送钉钉 ----------
# 转义双引号和反斜杠（防止 JSON 损坏）
#MESSAGE_ESCAPED=$(echo "$MESSAGE" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')


OUT_MSG=$(echo "🎉\r\n通知-标准 \n ### ##  ${MESSAGE} ### ")
echo " - OUT_MSG: ${OUT_MSG}"
# 构造 JSON 负载（注意：钉钉 Markdown 内容不能包含未转义的控制字符）
PAYLOAD="{\"msgtype\":\"markdown\",\"markdown\":{\"title\":\"[notify]服务器巡检报告\",\"text\":\"${OUT_MSG}\"}}"

# 发送请求
RESPONSE=$(curl -s -X POST "$WEBHOOK_URL" -H "Content-Type: application/json" -d "$PAYLOAD")

# 检查发送结果
if echo "$RESPONSE" | grep -q '"errcode":0'; then
    echo "✅ 巡检报告已成功发送至钉钉。"
else
    echo "❌ 发送失败，返回信息：$RESPONSE"
    exit 1
fi