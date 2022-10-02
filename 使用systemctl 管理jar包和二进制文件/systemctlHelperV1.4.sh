#!bin/bash
# 将 jar 包或者二进制包托管给 systemctl。 通过systemctl start/stop/status XXX 管理服务
# 作者: 赵文光
# 电话: 13810398818
# 版本: 1.4


############### 变量设置区 ###############
# 服务列表数组
declare -A ServicesList
declare -A CMD

# 静默模式,默认是关闭的
isSilent="n"

# 日志开关,默认是关闭; 使用 -s （silence）选项的时候，才会启动写日志
isWriteLog="n"

# 服务错误重启开关,默认是 'n' 号; 设置为'y'，则开启
failRestart='n'

# 全局变量，函数与主程序之间传递数据时使用。千万不要修改
ServiceName=""
programPath=""
Bin=""
jarPackage=""
params=""
serviceFile=""
CMD=""

############### 函数定义区 ###############

# 确认函数
## alert 有三个参数，第一个是提示语，第二和第三个参数用来匹配用户的输入（必须小写）
## 用户输入的等于第二个参数返回状态码为1， 输入的等于第三个参数返回 0
## 示例： alert "你确定吗？(yes/no)" "no" "yes"
alert(){
  while :;do
    echo -en " \e[1;33m $1 \e[0m";read flag
    flag=`echo $flag | tr [:upper:] [:lower:]`
    if [ "$flag" == "$2" ];then
      return 1
    elif [ "$flag" == "$3" ];then
      return 0;
    else
      echo -e "\033[1;31m 输入有误，请重新输入 \033[0m"
    fi
  done
}

# 写日志函数
## 有两个参数
## $1 写入 log 的内容
## $2 写入的 log 文件
## 示例 writeLog "服务启动成功" ${log_dir}/start_stop.log
writeLog(){
  if [ "$isWriteLog" == "y" ];then
    echo -e "[`date +'%Y-%m-%d %H:%M:%S'`] $1" >> $2
  fi
  return
}

# 异常
## 需要一个参数
## $1 异常的内容
exception(){
    if [ "$isWriteLog" == "y" ];then
        writeLog "$1" "${binDir}/systemHelper.log"
        echo -e "\e[1;33;41m $1 \e[0m"
        exit 2
    else
        echo -e "\e[1;33;41m $1 \e[0m"
        exit 2
    fi
}

# 根据脚本参数设置全局变量
## 需要一个参数，用来解析
parameterAnalysis(){
    case $1 in
        -s)
            isSilent="y"
            isWriteLog="y"
            ;;
        "")
            ;;
        *)
            describe
            exit 3
            ;;
            
    esac
}


# 获取配置文件的内容，封装到 ServicesList 中
## 依赖 ServicesList 字典
## 直接调用不需要任何参数
getConfig(){

    local line
    local tmp
    

    # 判断 ServicesList.conf 是否存在
    if [ ! -f "ServicesList.conf" ]; then
        createServicesListFile
        echo -e "\e[1;33;41m 请先设置 ${currentDir}/ServicesList.conf 文件 \e[0m"
        exit 1
    fi 


    # 循环读取文件内容
    while read -r line
    do
        line=`echo $line | grep -E "^[^#]"`
        [ "" == "$line" ] && continue

        # 确保 [] 在其他参数之前配置
        if [ "$serviceName" == "" ];then
            echo "$line" | grep -q "^\[[^]+]"
            if [ "$?" -ne 0 ];then
                exception "[] 应该在其他参数之前设置，重新配置 ${currentDir}/ServicesList.conf 文件"
            fi
            if [ "$isSilent" == "y" ];then
                writeLog " \n=============== ServicesList.conf 的内容 ===============" "${binDir}/systemHelper.log"
            fi
        fi

        if [ "$isSilent" == "y" ];then
            writeLog "${line}" "${binDir}/systemHelper.log"
        fi

        tmp=${line%%=*}
        case $tmp in
            [*)
                tmp=`echo "$tmp" | sed -r s/[[:space:]]+//g`
                if [ "$tmp" == "[]" ];then
                    exception "[] 不能为空，重新配置 ${currentDir}/ServicesList.conf 文件"
                fi
                serviceName=$(echo $tmp | tr -d '[' | tr -d ']')
            ;;
            programPath)
                ServicesList["$serviceName"]="${ServicesList["$serviceName"]}#${line}"
            ;;
            Bin)
                ServicesList["$serviceName"]="${ServicesList["$serviceName"]}#${line}"
            ;;
                
            jarPackage)#
                ServicesList["$serviceName"]="${ServicesList["$serviceName"]}#${line}"
            ;;
            params)
                ServicesList["$serviceName"]="${ServicesList["$serviceName"]}#${line}"
            ;;
            *)
        esac 
    done < ServicesList.conf
    if [ "$isSilent" == "y" ];then
        writeLog "=============================================" "${binDir}/systemHelper.log"
    fi 
}

# 检测配置文件正确性函数
## 需要一个参数
## $1 服务名
## 依赖 全局变量
checkServicesConfig(){
    programPath="${programPath#programPath=}" 
    Bin=${Bin#Bin=}
    Bin_without_dir=${Bin##*/}
    BinTmp=${Bin_without_dir%.*}
    jarPackage=${jarPackage#jarPackage=}
    jarPackage_without_dir=${jarPackage##*/}
    jarPackageTmp=${jarPackage_without_dir%.*}
    params=${params#params=}

   
    #判断 programPath 指定的目录是否存在
    if [ ! -d "${programPath}" ] && [ "" != "${programPath}" ];then
        exception "ServicesList.conf 文件中 ${ServiceName} 服务的 programPath 选项指定的路径不存在；请先设置 ${currentDir}/ServicesList.conf 文件"
    fi
    # 如果 programPath 没有指定，则赋值为当前目录
    if [ "" == "${programPath}" ];then
        programPath="${currentDir}"
    else
        # 如果programPath 是相对路径，就转换成绝对路径
        programPath="$(cd "${programPath}";pwd)"
    fi
    # 判断 Bin 是否为空
    if [ "${Bin}" == "" ];then
        exception "ServicesList.conf 文件中 ${ServiceName} 服务的 Bin 不能为空，请先设置 ${currentDir}/ServicesList.conf  文件"
    fi
    # 判断 Bin 变量指定的文件是否存在
    if [ ! -e ${programPath}/"${Bin_without_dir}" ] && [[ "${Bin_without_dir}" != java* ]];then
        exception "${ServiceName} 服务配置段指定的 ${programPath} 目录中不存在 ${Bin_without_dir} 程序,请重新设置 ${currentDir}/ServicesList.conf 文件"
    fi
    # 判断 jarPackage_without_dir 变量指定的文件是否存在
    if [ ! -e "${programPath}/${jarPackage_without_dir}" ] && [ "" != "${jarPackage_without_dir}" ];then
        exception "${ServiceName} 服务配置段指定的${programPath} 目录中不存在 ${jarPackage_without_dir}，请重新设置 ${currentDir}/ServicesList.conf 文件"
    fi
    # 判断 Bin 变量指定的程序是否是java
    if [[ "${Bin_without_dir}" != java* ]];then
        # 不是 java 判断是否有执行权限
        if [ ! -x "${programPath}/${Bin_without_dir}" ];then
            exception "${programPath}/${Bin_without_dir} 没有执行权限，请先使用 chmod 添加权限"
        fi
        # 给 Bin 重新赋值
        Bin=${programPath}/${Bin_without_dir}
        # 不是 java 程序，jarPackage 选项应该为空
        if [ "" != "${jarPackage_without_dir}" ];then
            exception "ServicesList.conf 文件中 ${ServiceName} 服务的 Bin 选项不是 java， jarPackage 选项应该为空，请先设置 ${currentDir}/ServicesList.conf 文件"
        fi
    else
        # 是 java 程序，Bin 要以 -jar 结尾
        echo ${Bin_without_dir} | grep -q "\-jar$"
        if [ $? -ne 0 ];then
            exception "ServicesList.conf 文件中 ${ServiceName} 服务的 Bin 选项如果是 java 命令， 要以 -jar 结尾，请先设置 ${currentDir}/ServicesList.conf 文件"
        fi
        # 是 java 程序，jarPackage不能为空
        if [ "" == "${jarPackage_without_dir}" ];then
            exception "ServicesList.conf 文件中 ${ServiceName} 服务的 Bin 选项是 java， jarPackage 选项应该填写当前目录下提供服务的 jar 包的包名，请先设置 ${currentDir}/ServicesList.conf 文件"
        fi
        # 重新给 Bin 和 jarPachakge 赋值
        Bin=$(which java)${Bin_without_dir#java}
        jarPackage="${programPath}/${jarPackage_without_dir}"
    fi
    # 判断为 systemctl 生成的 service 文件是否已经存在
    serviceFile="/usr/lib/systemd/system/${ServiceName}.service"
    if [ -e "$serviceFile" ];then
        exception "$serviceFile已存在，请联系系统管理员"
    fi
    # 拼接命令
    CMD="nohup ${Bin} ${jarPackage} ${params} >>${programPath}/nohup.out 2>&1  &"
    if [ "$isSilent" == 'n' ];then
        # 询问拼接的命令是否正确
        echo -e " \e[1;33m ${CMD} \e[0m" 
        alert "上面拼接的 ${ServiceName} 服务的启动命令是否正确？ (yes/no)" "no" "yes"
        if [ "$?" == "1" ];then
            echo -e "\e[1;33;41m 请重新编写 ${currentDir}/ServicesList.conf 文件 \e[0m"
            exit 1
        fi
    fi
    
}

# ServicesList元素重新赋值
# 需要一个参数
# $1 ServiceName
replaceServiceConfigList(){
    ServicesList[${1}]="#programPath=${programPath}#Bin=${Bin}#jarPachakge=${jarPachakge}#params=${params}#CMD=${CMD}#serviceFile=${serviceFile}"
}

# 文件说明函数
## 直接调用不需要任何参数
describe(){
    cat <<EOF
[33m
############### 说明 ###############
# 功能： 生成 systemctl 用到的 start、stop脚本和 service 文件，实现通过 systemctl 命令管理服务
#
# 注意：要将托管给 systemctl 管理的 “jar 包”或“二进制文件”的各种“参数”写到 ServicesList.conf 文件中，
# 
# 参数：-h 显示描述信息
#       -s (silence)安静模式，不提示自动删除配置文件，不提示自动启动服务, 将 $0 的运行情况和配置文件的内容写入到 ${binDir} 目录下的 systemHelper.log 文件 
#
#
# 目标服务的启动命令：systemctl start ?????
# 目标服务的服务停止命令：systemctl stop ?????
# 目标服务的服务状态查看命令：systemctl status ?????
[0m
EOF
}

prompt(){
    if [ ${isSilent} == "y" ];then
        systemctl start ${ServiceName}
        sleep 10
        systemctl status ${ServiceName} |grep -q "active"
        if [ "$?" == "0" ];then
            writeLog "${ServiceName} 已经启动" "${binDir}/systemHelper.log"
        else
            writeLog "${ServiceName} 启动失败" "${binDir}/systemHelper.log"     
        fi

        writeLog "${ServiceName} 服务的启动命令是：systemctl start ${ServiceName}" "${binDir}/systemHelper.log"
        writeLog "${ServiceName} 服务的停止命令是：systemctl stop ${ServiceName}" "${binDir}/systemHelper.log"
        writeLog "${ServiceName} 服务的状态查看命令是：systemctl status ${ServiceName}" "${binDir}/systemHelper.log"
        echo ${Bin} |grep -q ".sh$"
        if [ $? == 0 ];then
            writeLog "启动脚本套用了脚本，需要通过 ps 命令确认服务进程号是否与${programPath}/${ServiceName}.pid中的内容相同，如果不同，则需要修改${ServiceName}Start.sh文件，启用文件末尾注释掉的代码" "${binDir}/systemHelper.log" 
        fi  

    else
        # 启动服务
        alert "是否启动 ${ServiceName} 服务 ？ (yes/no)" "no" "yes"
        if [ "$?" == "0" ];then
            systemctl start ${ServiceName}
        fi
        # 显示启动命令
        echo -e "\e[1;33;42m ${ServiceName} 服务的启动命令是：systemctl start ${ServiceName} \e[0m"
        # 显示停止命令
        echo -e "\e[1;33;42m ${ServiceName} 服务的停止命令是：systemctl stop ${ServiceName} \e[0m"
        # 显示查看状态命令
        echo -e "\e[1;33;42m ${ServiceName} 服务的状态查看命令是：systemctl status ${ServiceName} \e[0m"
        # 如果是嵌套脚本启动的需要用户手动修改启动文件
        echo ${Bin} |grep -q ".sh$"
        if [ $? == 0 ];then
            echo -e "\e[1;33;41m 启动脚本套用了脚本，需要通过 ps 命令确认服务进程号是否与${programPath}/${ServiceName}.pid中的内容相同，如果不同，则需要修改${ServiceName}Start.sh文件，启用文件末尾注释掉的代码 \e[0m"   
        fi  
    fi
}

# 创建所有的文件
creatFiles(){
    # 创建 start.sh 文件,并赋予执行权限
    createStartFile
    chmod +x ${programPath}/${ServiceName}Start.sh

    # 创建 stop.sh 文件,并赋予执行权限
    createStopFile
    chmod +x ${programPath}/${ServiceName}Stop.sh

    # 创建 service 文件
    createServiceFile

    #重新加载systemctl自身的配置文件
    systemctl daemon-reload

    # 添加到开机启动
    systemctl enable ${ServiceName}
    writeLog "$ServiceName 已添加到开机启动项" "${binDir}/systemHelper.log"
}

# 创建配置文件函数
## 直接调用不需要任何参数
createServicesListFile(){
    cat >${currentDir}/ServicesList.conf <<EOF 
# [] 中括号内填写服务名（给服务起个名字）
# 不能为空
#示例：[test1]
[]

# 程序 或者 jar 包所在路径
## 默认是当前路径
## programPath=/data/service
programPath=

# 命令,如果是 java 程序就写 java -jar ；如果是启动脚本，就写脚本名
## 此选项不要包含路径，路径将被忽略
## 示例1 Bin=java -jar
## 示例2 Bin=zkServer.sh
Bin=

# jar/war 包, 如果不是 java 程序，就什么也不填
## 此选项不要包含路径，路径将被忽略
## 示例 jarPackage=test.jar
jarPackage=

# 参数，输入命令用到的参数。
## -Dlog4j2.formatMsgNoLookups=true 这个是针对 log4j 低版本漏洞的一个参数
## 示例 params=-Dlog4j2.formatMsgNoLookups=true -Xmx2048m
params=


##### 支持配置多个服务
# [test2]
# programPath=/opt/services/test2
# Bin=java -jar
# jarPackage=test2.jar
# params=-Dlog4j2.formatMsgNoLookups=true -Xmx2048m
 
 
###### 注意：等号两边不要有多余的空格 ######
EOF
}

# 创建start.sh文件函数
## 直接调用不需要任何参数
createStartFile(){
    cat >${programPath}/${ServiceName}Start.sh <<EOF
#!/bin/bash

# 获取本脚本所在的目录
cd \$(dirname "\$0")
binDir=\$(pwd)

# 启动服务
${CMD}

# 将进程号写入以jar包或者二进制文件名开头的 pid 文件。
echo \$! > \${binDir}/${ServiceName}.pid



########## 如果启动脚本出现了嵌套的情况。真实的 pid 与pid文件内容不同的时候，需要启用下面的代码，并手动修改Command_line变量的值来获得程序的正确进程号 ##########
# 使用 ps 命令查看服务真正的进程号，并与${binDir}/${ServiceName}.pid 对比。如果不同，则复制 /proc/真正进程号/cmdline 文件中的内容，赋值给Command_line变量。
## 示例：Command_line=$(echo "${Bin}${jarPackage}${params}" | sed s/[[:space:]]*//g)

#Command_line=

## 获取本机所有的进程号
#sleep 1
#programs=\$(ls /proc |grep -P "\d+")

## 扫描进程文件夹， 将进程号写入 ${binDir}/${ServiceName}.pid 文件
#for i in \$programs;
#do
#   cd /proc/\$i 2>/dev/null
#   cmdLine=\$(tail cmdline)
#   if [ "\$Command_line" == "\$cmdLine" ];then
#       echo \$i > \${binDir}/${ServiceName}.pid
#       exit 0
#   fi
#done
EOF
    writeLog "${programPath}/${ServiceName}Start.sh 文件创建完成" "${binDir}/systemHelper.log"
}

# 创建stop.sh文件函数
## 直接调用不需要任何参数
createStopFile(){
    cat >${programPath}/${ServiceName}Stop.sh <<EOF
#!/bin/bash

# 切换目录
cd \$(dirname "\$0")
binDir=\$(pwd)

# 关闭进程
kill \$(cat \${binDir}/${ServiceName}.pid)
#rm -fr ${ServiceName}.pid
EOF
writeLog "${programPath}/${ServiceName}Stop.sh 文件创建完成" "${binDir}/systemHelper.log"
}

# 创建 Service 文件函数
## 直接调用不需要任何参数
createServiceFile(){
    [ "$failRestart" == "n" ] && failRestart='#'
    [ "$failRestart" == "y" ] && failRestart=''
    cat >$serviceFile <<EOF
[Unit]
Description=The ${ServiceName} server
After=network.target remote-fs.target nss-lookup.target
[Service]
Type=forking
PIDFile=${programPath}/${ServiceName}.pid
ExecStart=${programPath}/${ServiceName}Start.sh
ExecStop=${programPath}/${ServiceName}Stop.sh
ExecStartPost=/bin/sleep 0.1
${failRestart}RestartSec=10
PrivateTmp=true
${failRestart}Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
writeLog "$serviceFile 文件创建完成" "${binDir}/systemHelper.log"
}

# 删除配置文件
## 不需要参数， 直接调用
delServicesListConfigFile(){
    if [ ${isSilent} == "y" ];then
        rm -fr ServicesList.conf
        echo -e "\e[1;33;42m 脚本运行结束，有问题请查看 ${binDir}/systemHelper.log 日志文件 \e[0m"
        writeLog "脚本运行结束\n" "${binDir}/systemHelper.log"
    else
        # 询问是否删除 ServicesList.conf 文件
        alert "是否删除 ServicesList.conf 文件? (yes/no)" "no" "yes"
        if [ "$?" == "0" ];then
            rm -fr ServicesList.conf
        fi
        echo -e "\e[1;33;42m 脚本运行结束 \e[0m"
    fi
}


############### 主程序 ###############

# 获取当前路径
currentDir=$(pwd)
# 获取本脚本所在路径
binDir=$(cd $(dirname $0);pwd)
# 解析本脚本的入参
parameterAnalysis $*
# 获取要配置的服务列表
getConfig 
# 遍历 ServicesList 字典，检查配置文件是否正确
for ServiceName in ${!ServicesList[*]};do   
    programPath=`echo "${ServicesList[$ServiceName]}" | sed -r 's/.*#programPath=([^#]*).*/\1/g'`
    Bin=`echo "${ServicesList[$ServiceName]}" | sed -r 's/.*#Bin=([^#]*).*/\1/g'`
    jarPackage=`echo "${ServicesList[$ServiceName]}" | sed -r 's/.*#jarPackage=([^#]*).*/\1/g'`
    params=`echo "${ServicesList[$ServiceName]}" | sed -r 's/.*#params=([^#]*).*/\1/g'`
 
    # 检查配置文件是否正确
    checkServicesConfig
    replaceServiceConfigList ${ServiceName}
done
# 遍历 ServicesList 字典，部署每一个服务
for ServiceName in ${!ServicesList[*]};do
    programPath=`echo "${ServicesList[$ServiceName]}" | sed -r 's/.*#programPath=([^#]*).*/\1/g'`
    CMD=`echo "${ServicesList[$ServiceName]}" | sed -r 's/.*#CMD=([^#]*).*/\1/g'`
    Bin=`echo "${ServicesList[$ServiceName]}" | sed -r 's/.*#Bin=([^#]*).*/\1/g'`
    jarPackage=`echo "${ServicesList[$ServiceName]}" | sed -r 's/.*#jarPackage=([^#]*).*/\1/g'`
    params=`echo "${ServicesList[$ServiceName]}" | sed -r 's/.*#params=([^#]*).*/\1/g'`
    serviceFile=`echo "${ServicesList[$ServiceName]}" | sed -r 's/.*#serviceFile=([^#]*).*/\1/g'`
    
    # 创建文件
    creatFiles
    # 启动服务并生成提示信息
    prompt
done
# 删除配置文件
delServicesListConfigFile



