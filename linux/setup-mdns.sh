#!/bin/bash

# 1. 도메인 인자가 없는 경우 대화형으로 입력 받기
if [ $# -eq 0 ]; then
    echo "--------------------------------------------------------"
    echo " mDNS 도메인 설정 도우미"
    echo "--------------------------------------------------------"
    echo "설정할 도메인 이름을 입력해주세요."
    echo "여러 개를 설정하려면 공백으로 구분하여 입력하세요. (예: api sensor log)"
    echo "(.local은 자동으로 추가되므로 입력하지 않으셔도 됩니다.)"
    echo "--------------------------------------------------------"
    read -p "입력: " USER_INPUT
    
    # 입력값이 없으면 종료
    if [ -z "$USER_INPUT" ]; then
        echo "입력값이 없어 설정을 종료합니다."
        exit 1
    fi
    set -- $USER_INPUT
fi

# 2. .local 자동 접미사 처리
# 입력받은 모든 인자에 대해 .local이 없으면 붙여줌
FINAL_DOMAINS=""
for arg in "$@"; do
    if [[ ! $arg == *.local ]]; then
        arg="$arg.local"
    fi
    FINAL_DOMAINS="$FINAL_DOMAINS $arg"
done

echo "다음 도메인들이 등록됩니다:$FINAL_DOMAINS"

# 3. 필수 패키지 및 방화벽 설정
# [설치] 패키지명은 'avahi'입니다.
sudo dnf install -y python3-avahi python3-dbus avahi nss-mdns

# [실행] 서비스명은 'avahi-daemon'입니다.
sudo systemctl enable --now avahi-daemon

# [방화벽] mdns 서비스를 허용합니다.
sudo firewall-cmd --permanent --add-service=mdns
sudo firewall-cmd --reload

# 4. mDNS 실행용 파이썬 스크립트 생성
cat << 'EOF' > /usr/local/bin/mdns-runner.py
import sys, avahi, dbus, time

def register(name):
    try:
        bus = dbus.SystemBus()
        server = dbus.Interface(bus.get_object(avahi.DBUS_NAME, avahi.DBUS_PATH_SERVER), avahi.DBUS_INTERFACE_SERVER)
        group = dbus.Interface(bus.get_object(avahi.DBUS_NAME, server.EntryGroupNew()), avahi.DBUS_INTERFACE_ENTRY_GROUP)
        group.AddService(avahi.IF_UNSPEC, avahi.PROTO_UNSPEC, 0, name, "_http._tcp", "", "", 80, [])
        group.Commit()
        print(f"Successfully registered: {name}")
    except Exception as e:
        print(f"Failed to register {name}: {e}")

if __name__ == "__main__":
    for domain in sys.argv[1:]:
        register(domain)
    while True: time.sleep(60)
EOF

# 5. Systemd 서비스 등록
cat << EOF > /etc/systemd/system/mdns-custom.service
[Unit]
Description=Dynamic mDNS Custom Alias Service
After=network-online.target avahi-daemon.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/mdns-runner.py $FINAL_DOMAINS
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 6. 서비스 활성화 및 시작
sudo systemctl daemon-reload
sudo systemctl enable --now mdns-custom.service

echo "--------------------------------------------------------"
echo "설정이 완료되었습니다!"
echo "이제 네트워크에서 다음 주소로 접속 가능합니다:$FINAL_DOMAINS"
