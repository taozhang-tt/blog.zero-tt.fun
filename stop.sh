hugo_pid=`lsof -t -i:1313`
if [ $hugo_pid ]
then 
    kill -9 $hugo_pid
fi
