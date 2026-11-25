#!/bin/bash
# Cài APK lên máy ảo, mở app, chụp màn hình, kiểm tra không bị văng.
set -x
PKG=vn.bentic.bclean.debug
APK=$(ls dist/*.apk | head -1)
mkdir -p shots samples

# Ảnh mẫu: 3 ảnh trùng + 2 ảnh khác
convert -size 1200x900 gradient:teal-blue samples/a1.jpg
cp samples/a1.jpg samples/a2.jpg; cp samples/a1.jpg samples/a3.jpg
convert -size 1200x900 plasma:fractal samples/b1.jpg
convert -size 900x1200 xc:orange -fill white -draw "circle 450,600 450,300" samples/c1.jpg

adb wait-for-device
adb install -r "$APK" || exit 1
# Nạp ảnh mẫu qua MediaStore (cách chắc chắn trên Android 11+)
for f in samples/*.jpg; do
  n=$(basename $f)
  adb shell content insert --uri content://media/external/images/media \
    --bind _display_name:s:$n --bind relative_path:s:Pictures/BcleanTest/ --bind mime_type:s:image/jpeg
  ID=$(adb shell content query --uri content://media/external/images/media --projection _id:_display_name | grep "_display_name=$n" | grep -oE '_id=[0-9]+' | tail -1 | cut -d= -f2)
  echo "inserted $n as $ID"
  cat "$f" | adb shell content write --uri content://media/external/images/media/$ID
done
sleep 3
adb shell content query --uri content://media/external/images/media --projection _id:_display_name:_size:width:height
adb logcat -c

# 1. Màn hình chào (lần đầu mở)
adb shell am start -W -n $PKG/vn.bentic.bclean.MainActivity
sleep 8
adb exec-out screencap -p > shots/1-onboarding.png

# 2. Bỏ qua onboarding + cấp quyền, mở lại → Dashboard quét ảnh
adb shell am force-stop $PKG
cat > bclean.xml <<XML
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map><boolean name="onboarded" value="true" /></map>
XML
adb push bclean.xml /data/local/tmp/bclean.xml
adb shell "run-as $PKG sh -c 'mkdir -p shared_prefs && cp /data/local/tmp/bclean.xml shared_prefs/bclean.xml'"
adb shell pm grant $PKG android.permission.READ_MEDIA_IMAGES
adb shell pm grant $PKG android.permission.READ_MEDIA_VIDEO
adb shell am start -W -n $PKG/vn.bentic.bclean.MainActivity
sleep 20
adb exec-out screencap -p > shots/2-dashboard.png

# 3. Mở nhóm "Ảnh trùng" (thẻ đầu tiên, góc trái lưới)
SIZE=$(adb shell wm size | grep -oE '[0-9]+x[0-9]+' | tail -1); W=${SIZE%x*}; H=${SIZE#*x}
adb shell input tap $((W*26/100)) $((H*58/100))
sleep 4
adb exec-out screencap -p > shots/3-duplicates.png
adb shell input keyevent KEYCODE_BACK
sleep 2

# 4. Tab Lướt ảnh
adb shell input tap $((W*3/8)) $((H-80))
sleep 5
adb exec-out screencap -p > shots/4-swipe.png

adb logcat -d > shots/logcat.txt
grep -E "FATAL EXCEPTION|AndroidRuntime: Process: $PKG" shots/logcat.txt && { echo "❌ App bị văng"; grep -A30 "FATAL EXCEPTION" shots/logcat.txt | head -60; exit 1; }
grep "BcleanAnalytics" shots/logcat.txt | tail -10
echo "✅ Không có crash"
exit 0
