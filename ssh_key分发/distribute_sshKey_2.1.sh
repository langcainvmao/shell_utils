#!/bin/bash
#
#********************************************************************
#Author:        Zhao Wenguang
#
#QQ:             464586910
#
#Date:             2018-12-17
#
#FileName：        distribute_key.sh
#
#URL:             http://github.com/langcainvmao
#
#Description：        用于分发ssh公钥，实现免密登录，更改ssh端口    
#
#Copyright (C):     2018 All rights reserved
#********************************************************************

#**********************#
#      变量声明        #
#**********************#
#SSH 用户名
ssh_user_name="root"

#SSH 密码,（出于安全考虑，建议此处为空,根据提示手动输入）
ssh_password="这里填写密码"

#SSH 端口
ssh_port=22

#保存 IP 地址列表的文件
ip_list_file=iplist.txt

#备份文件夹（如果原来有密钥对，会移动到该目录）
backup_dir="ssh.bak"

# 日志存放目录
log_dir="./distribute_log"

# log 日志文件
log_file=${log_dir}/"distribute.log"

#用于传递参数，保存离线主机临时列表
offline_file=${log_dir}/"offline_host_list.txt"

#用于传递参数，保存分发失败主机的临时列表
fail_file=${log_dir}/"distribute_fail_list.txt"


#用于传递参数，保存分发成功主机的临时列表
ok_file=${log_dir}/"distribute_ok_list.txt"


#用于传递参数，保存原来成功分发过key，本次不需要分发key的主机的临时列表
already_had_key_file=${log_dir}/"distribute_already_had_list.txt"


#新的ssh端口
new_ssh_port=22

#设置 ssh 连接等待时间
ssh_wait_time=60

#是否写日志
isWriteLog=y

#**********************#
#      函数声明        #
#**********************#

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
        writeLog "$1" "${log_dir}/distribute_err.log"
        echo -e "\e[1;33;41m $1 \e[0m"
        exit 2
    else
        echo -e "\e[1;33;41m $1 \e[0m"
        exit 2
    fi
}

detect_iplist(){
    if [ ! -f "${ip_list_file}" ];then
        exception "服务器列表文件 ${ip_list_file} 不存在\n-----iplist 文件示例如下-----\n10.116.28.191\n10.116.28.190\n10.116.28.192\n"
    fi
#echo -e "\e[1;33;41m -----iplist 文件示例如下-----\n \e[0m"
#echo -e "10.116.28.191\n10.116.28.190\n10.116.28.192\n"

}


#检测 expect 软件是否安装
detect_soft(){
    rpm -q expect
    if [ $? -ne 0 ]; then
        yum install -y expect 
        [ $? -ne 0 ] && exception "Installed expect failed,please install the expect manually"
    fi

}

#判断主机是否在线
detect_host(){
    ping -w1 $1 &> /dev/null
    if [ $? -eq 0 ]; then
        return 0
    else
        if [ -n "$1" ] ;then
            echo $1 >> $offline_file
        fi
        return 1
    fi
}
#判断能否使用ssh免密登陆
test_ssh_nopassword(){
        expect << endoffile
        spawn ssh $ssh_user_name@$ipaddr -p $ssh_port
        set timeout $ssh_wait_time
        expect {
            "*yes/no*" { send "yes\r";exp_continue }
                "*password*" { exit 126 }
                "*Last login:*" { exit 0 }
                timeout { exit 127 }
        }
    expect eof
endoffile
    [ $? -eq 0 ] && return 0 || return 1
}

#分发ssh_key (需要调用 detect_soft , detect_host 和 test_ssh_nopassword函数)
distribute_key(){
    detect_iplist
    cd ~
    if [ -f ".ssh/id_rsa" ] || [ -f ".ssh/id_rsa.pub" ] ;then
        alert "检测到本机秘钥文件已存在，是否更新，更新会导致原来分发过秘钥的主机失效(yes/no)？" "no" "yes"
        if [ "$?" == "0" ];then
            mv -f --backup=number ~/.ssh/id_rsa{,bak}
            mv -f --backup=number ~/.ssh/id_rsa.pub{,bak}
            ssh-keygen -t rsa -P "" -f /root/.ssh/id_rsa
            [ "$?" == "0" ] && writeLog "秘钥生成成功" "${log_file}"
        fi
    else
      ssh-keygen -t rsa -P "" -f /root/.ssh/id_rsa
      [ "$?" == "0" ] && writeLog "秘钥生成成功" "${log_file}"
    fi
    cd - > /dev/null
    detect_soft
    while read ipaddr ; do
        {
            detect_host $ipaddr
            if [ $? -ne 0 ] ;then				
				continue
			fi
			test_ssh_nopassword
			if [ $? -eq 0 ];then
			    echo $ipaddr >> ${already_had_key_file}
				continue
			fi
            expect <<EOF
            set timeout $ssh_wait_time
            spawn ssh-copy-id  -p $ssh_port -i /root/.ssh/id_rsa.pub $ssh_user_name@$ipaddr 
            expect {
                "yes/no" { send "yes\n";exp_continue }
                "password" { send "$ssh_password\n" }
            }
            expect eof
EOF
            if [ $? -ne 0 ] ;then
                echo $ipaddr >> $fail_file
            else
                test_ssh_nopassword            
                [ $? -eq 0 ] && echo $ipaddr >> $ok_file ||  echo $ipaddr>> $fail_file 
            fi
        }&
    done < $ip_list_file
    wait
}

#打印分发失败主机列表
print_result() {
    if [ -f "$offline_file" ] ;then
        echo "====================================="
        echo -e "\033[1;31m""Offline hosts \033[0m"
        cat $offline_file | while read list; do
        echo -e "\033[1;31m$list\033[0m"
        done
        echo "====================================="

    fi
    if [ -f $fail_file ];then
        echo "====================================="
        echo -e "\033[1;31m""Failed hosts \033[0m"
        cat $fail_file | while read list; do
        echo -e "\033[1;31m$list\033[0m"
        done
        echo "====================================="
    fi
    if [ -f $ok_file ];then
        echo "====================================="
        echo -e "\033[1;32m""Succeed hosts \033[0m"
        cat $ok_file | while read list; do
        echo -e "\033[1;32m$list\033[0m"
        done
        echo "====================================="
    fi
    if [ -f ${already_had_key_file} ];then
        echo "====================================="
        echo -e "\033[1;32m""already had key before hosts \033[0m"
        cat ${already_had_key_file} | while read list; do
        echo -e "\033[1;32m$list\033[0m"
        done
        echo "====================================="
    fi 	
}

#取得系统主版本号
get_system_version() {
    version=`cat /etc/redhat-release | sed -rn 's/([^[:digit:]])+([0-9]).*/\2/p'`
}

#设置新的ssh端口（需要调用get_system_version函数）
set_ssh_port () {
    sed -ir '/^[Pp]ort /d ' /etc/ssh/sshd_config
    sed -ir "/#Port 22/aPort $new_ssh_port" /etc/ssh/sshd_config
    get_system_version
    if [ $version -eq 7 ];then
        systemctl restart sshd
    elif [ $version -eq 6 ];then
        service sshd restart
    else
        service sshd restart
    fi

}

#**********************#
#      程序主体        #
#**********************#
#输入ssh密码
[ -z "$ssh_password" ] && read -s -p "Please input the [1;033mPASSWORD[0m of ssh: " ssh_password

# 创建目录日志
[ -d "${log_dir}" ] || mkdir -p ${log_dir}

#分发密钥
distribute_key

#打印离线主机的列表
print_result

#修改ssh端口
#set_ssh_port

#将成功失败的信息，写日志
writeLog "-----Succeed hosts-----" ${log_file}
[ -f "${ok_file}" ] &&cat ${ok_file} |sort >> ${log_file}
writeLog "-----already had key before hosts-----" ${log_file}
[ -f "${already_had_key_file}" ] &&cat ${already_had_key_file} |sort >> ${log_file}
writeLog "-----failed hosts-----" ${log_file}
[ -f "${fail_file}" ] && cat ${fail_file} |sort >> ${log_file}
writeLog "-----offline_host-----" ${log_file}
[ -f "${offline_file}" ] &&cat ${offline_file} |sort >> ${log_file}
writeLog "----------------------" ${log_file}


#清除临时文件
rm -fr $ok_file $fail_file $offline_file ${already_had_key_file}

#注销变量
unset ssh_user_name ssh_password ssh_port new_ssh_port ip_list_file already_had_key_file

