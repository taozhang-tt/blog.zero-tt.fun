hugo_pid=`lsof -t -i:1313`
if [ $hugo_pid ]
then 
    kill -9 $hugo_pid
fi
cd /root/blog.zero-tt.fun
hugo server -p=1313
