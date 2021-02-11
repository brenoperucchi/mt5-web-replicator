import pdb
import paramiko
import os

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
# ssh.load_system_host_keys()
ssh.load_host_keys(os.path.expanduser('~/.ssh/known_hosts'))
ssh.connect("benincasouza.tplinkdns.com", username="brenoperucchi", password="ASZX12qw", port=2222)

ssh_stdin, ssh_stdout, ssh_stderr = ssh.exec_command("conda run python c:/Devs/remotecall.py")
exit_code = ssh_stdout.channel.recv_exit_status() # handles async exit error 

for line in ssh_stdout:
    print(line.strip())