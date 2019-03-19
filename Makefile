JOIN=./video-join -v
TRIM=./video-trim -v
INSET=./video-inset -v
SCALE=./video-scale -v
HEADER_TRAILER=./video-header-trailer -v

OVERLAY=gpw2019-overlay.png
HEADER=gpw2019-header.MP4
TRAILER=gpw2019-trailer.MP4

# Find rate of recorded video
# ffprobe 2019-03-07-what-i-learned-about-sql-in-2018.joined.MP4 -select_streams v:0 -show_entries stream=r_frame_rate -of compact=p=0:nk=1
#RATE=25
#RATE=29.97
RATE=30000/1001
AUDIO_RATE=256k
TARGET_RESOLUTION=1920x1080
DURATION=5

%.yml : | %.1.MP4
	video-metadata $^ -o $@

$(HEADER) $(TRAILER): gpw2019-sponsors.png
	# -v must come from the video, sample_rate as well
	ffmpeg -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=48000" \
		-loop 1 -framerate $(RATE) -i $< -s $(TARGET_RESOLUTION) \
		-c:v libx264 -pix_fmt yuv420p -c:a aac -b:a $(AUDIO_RATE) -t $(DURATION) $@ -y

%.joined.MP4: %.[1234].MP4
	$(JOIN) $^ -o $@

%.trimmed.MP4: %.joined.MP4 %.yml
	$(TRIM) $^ -o $@

%.start.MP4: %.trimmed.MP4
	$(TRIM) $^ --start 00:00:00 --end 00:01:00 -o $@

%.end.MP4: %.trimmed.MP4
	$(TRIM) $^ --start -00:01:00 --end -00:00:00 -o $@

%.middle-unscaled.MP4: %.trimmed.MP4
	$(TRIM) $^ --start 00:01:00 --end -00:01:00 -o $@

%.middle.MP4: %.middle-unscaled.MP4
	$(SCALE) $^ --resolution $(TARGET_RESOLUTION) -o $@

%.inset-start.MP4: %.start.MP4 $(OVERLAY)
	$(INSET) --x 600 --y 40 $^ -o $@

%.inset-end.MP4: %.end.MP4 $(OVERLAY)
	$(INSET) --x 600 --y 40 $^ -o $@

%.final.MP4: $(HEADER) %.inset-start.MP4 %.middle.MP4 %.inset-end.MP4 $(TRAILER) %.yml
	$(JOIN) $^ -o $@
	# Prepend header
	# append trailer
	# upload?!
