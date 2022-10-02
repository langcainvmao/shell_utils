#!/bin/bash
# 功能：用于替换jar包中的依赖
# 作者：赵文光
# 联系方式：13810398818
# 版本 1.0

############### 变量设置区 ###############

# 扫描目录,写在一对双引号内，多个目录之间用空格分割,如果为空则全盘扫描。
# 示例 DIRS="/opt/server /data"
SCANDIRS=""

# 排除的目录，写在一对双引号内，多个目录之间用空格分割
EXCEPTDIRS="java-1.8.0-openjdk jdk1.8 bak /proc /run" 

# 获取本脚本所在目录
BASEDIR=$(dirname $0)
BASEDIR=$(cd $BASEDIR;pwd)

# 要替换的依赖jar包,如果具体版本不明确，版本信息可以省略
DEPENDECEJAR="BOOT-INF/lib/fastjson-"

# 新的依赖的 jar 包
NEWJAR="./fastjson-1.2.83.jar"

# 日志文件
LOGFILE="${BASEDIR}/replaceJar.log"

# 错误日志
ERRORLOG="${BASEDIR}/replaceJarError.log"

# 存放find排除的表达式( 用户不要修改 ) 
EXCEPTPATTEN=""

# 存放 jar 包的路径(用户不要修改)
JARS=""

# 存放 需要替换的 jar 包(用户不要修改)
NEEDREPLACEJARS=""
############### 函数定义区 ###############

# 确认函数
## alert 有三个参数，第一个是提示语，第二和第三个参数用来匹配用户的输入（必须小写）
## 用户输入的等于第二个参数返回状态码为1， 输入的等于第三个参数返回 0
## 示例： alert "你确定吗？(yes/no)" "no" "yes"
alert() {
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
writeLog() {
    echo -e "[`date +'%Y-%m-%d %H:%M:%S'`] $1" >> $2
}

# 异常
## 需要两个参数
## $1 异常的内容
## $2 写入的 log 文件
exception() {
    writeLog "$1" "$2"
    echo -e "\e[1;33;41m$1\e[0m"
    exit 2
}

# 备份
## 需要两个参数
## $1 要备份的文件
## $2 写入的 log 文件
backup() {
    local DIR=`dirname $1`
    DIR=$(cd $DIR;pwd)
    local fileName=`basename $1`
    local backDir=${DIR}/bak/`date +%Y-%m-%d-%H-%M-%S`
    mkdir -p $backDir
    cp "$1" "${backDir}"
    writeLog "将 ${DIR}/${fileName} 备份到 ${backDir} 目录下" "${LOGFILE}"
}

# 判断系统中是否有 jar 命令 （openjdk 默认是不提供的）
# 不需要参数
# 依赖 excepiton 函数
testJarexsit() {
    updatedb
    locate -b "\jar" | grep -qv "Docker"
    if [ "$?" -ne 0 ];then
        javaHome=$(dirname `locate -b "\java" |grep "openjdk.*bin"`)
        exception "系统中缺少 jar 命令，请从其他服务器拷贝 jar 命令到 ${javaHome}/ 目录下。然后给程序添加运行权限，并创建链接文件。命令如下：\n\t chmod +x ${javaHome}/jar \n\t ln -s ${javaHome}/jar /usr/bin/jar " "${ERRORLOG}"
    fi
}

# 判断是否依赖 fastjson 包
## 需要一个参数
## $1 jar 包的完整路径
## 返回状态为 0 是有依赖，返回状态为 1 是没有依赖
## 示例 fastjson /opt/server/aep-enable-openapi/aep-enable-openapi-1.0.0.jar
dependenceJar() {
    jar -tf $1 | grep -q "${DEPENDECEJAR}"
    [ "$?" -eq 0 ] && return 0 || return 1
}

# 替换 fastjson 包
## 需要一个参数
## $1 jar 包的完整路径
## 示例 fastjson /opt/server/aep-enable-openapi/aep-enable-openapi-1.0.0.jar
replaceJar() {
    local DIR=`dirname $1`
    DIR=$(cd $DIR;pwd)
    local fileName=`basename $1`
    mkdir ${DIR}/replaceJarTempDir
    mv $1 ${DIR}/replaceJarTempDir
    cd ${DIR}/replaceJarTempDir
    jar -xf ${DIR}/replaceJarTempDir/${fileName}
    cd - 1>/dev/null
    rm -fr ${DIR}/replaceJarTempDir/${fileName}
    rm -fr ${DIR}/replaceJarTempDir/${DEPENDECEJAR}*.jar
    cp ${NEWJAR} ${DIR}/replaceJarTempDir/BOOT-INF/lib/
    cd ${DIR}/replaceJarTempDir/
    jar -cfM0 $1 ./*
    cd - 1>/dev/null
    rm -fr ${DIR}/replaceJarTempDir
    writeLog "将 ${DIR}/${fileName} 中的 ${DEPENDECEJAR} 替换完成 " "${LOGFILE}"
}


############### 主程序 ###############
# 判断系新提供的 jar 包指定的路径是否正确
if [ ! -f "${NEWJAR}" ];then
    exception "替换用的 ${NEWJAR} 包不存在，请确保 $0 脚本 NEWJAR 变量指定的 jar 包存在" "${ERRORLOG}"
fi

# 判断系统中是否存在 jar 命令（openjdk 默认不提供）
testJarexsit

# 如果没有指定目录，则将目标目录设置为根目录
if [ "" == "${SCANDIRS}" ];then
    SCANDIRS="/"
    alert "扫描目录变量没有配置，默认将全盘扫描，是否继续（yes/no) " "yes" "no"
    [ "$?" == 0 ] && exit 1
fi

# 设置 find 排除的表达式
for DIR in $EXCEPTDIRS ;do
    EXCEPTPATTEN="${EXCEPTPATTEN} -path *${DIR}* -o"
done
EXCEPTPATTEN=${EXCEPTPATTEN%%-o}

echo -en "\033[1;31m扫描中，请耐心等待\033[0m"
for DIR in $SCANDIRS ;do
    if [ ! -d $DIR ];then
       exception "${DIR} 目录不存在，请重新设置 SCANDIRS 变量" "${ERRORLOG}"
    fi
    JARS="$JARS "`find ${DIR} -type d \( ${EXCEPTPATTEN} \) -prune -o \( -name "*.jar" -type f -print \)`
done

for JAR in $JARS;do
    echo -en "\033[1;31m.\033[0m"
    dependenceJar $JAR
    if [ "$?" == 0 ];then
        NEEDREPLACEJARS="${NEEDREPLACEJARS} $JAR"
    fi
done
echo

if [ "${NEEDREPLACEJARS}" == "" ];then
    echo -e "\e[1;33;42m没有找到需要替换的 jar 包 \e[0m"
    exit 0
else
    for JAR in ${NEEDREPLACEJARS}; do
        echo -e "\e[1;33;42m$JAR \e[0m"
    done
fi

alert "以上是需要替换依赖的 jar 包，是否全部替换？\n  如果只替换部分，请编辑 SCANDIRS 变量或 EXCEPTDIRS 变量 （yes/no）" no yes
if [ "$?" -eq 0 ];then
echo -en "\033[1;32m正在替换中，请耐心等待\033[0m"
    for JAR in ${NEEDREPLACEJARS}; do
        echo -en "\033[1;32m.\033[0m"
        backup "${JAR}"
        replaceJar ${JAR}
    done
else
    exit 0
fi
echo
echo -e "\033[1;32m替换完成\033[0m"