JOIN=./video-join -v
TRIM=./video-trim -v
INSET=./video-inset -v
STAMP=./video-overlay -v
SCALE=./video-scale -v
METADATA=./video-metadata -v
HEADER_TRAILER=./video-header-trailer -v

SHOW=German Perl Workshop 2019
OVERLAY=assets/gpw2019-overlay.png
HEADER=assets/gpw2019-header.mkv
TRAILER=assets/gpw2019-trailer.mkv

# Find rate of recorded video
# ffprobe 2019-03-07-what-i-learned-about-sql-in-2018.joined.MP4 -select_streams v:0 -show_entries stream=r_frame_rate -of compact=p=0:nk=1
#RATE=25
#RATE=29.97
#RATE=30000/1001

# ffprobe -v 0 -of csv=p=0 -select_streams v:0 -show_entries stream=r_frame_rate
RATE=25/1

AUDIO_RATE=256k

# ffprobe -v 0 -of csv=p=0 -select_streams a:0 -show_entries stream=sample_rate
AUDIO_SAMPLE_RATE=44100
# ffprobe -v error -select_streams v:0 -show_entries stream=height,width -of csv=s=x:p=0
TARGET_RESOLUTION=1920x1080
DURATION=5

JOINED_VIDEOS := $(subst .1.mkv,.joined.mkv,$(wildcard video/*.1.mkv))
VIDEOS := $(subst .joined.mkv,.final.mkv,$(wildcard video/*.joined.mkv))
METADATA_FILES := $(subst .joined.mkv,.yml,$(wildcard video/*.joined.mkv))

.PRECIOUS: %.yml %.middle.mkv
.PHONY: prepare-cut videos

metadata: $(METADATA_FILES)
prepare-cut: $(JOINED_VIDEOS) metadata
videos: $(VIDEOS)

%.yml : | %.joined.mkv
	$(METADATA) $^ $| --show "$(SHOW)" --language deu -o $@

$(HEADER) $(TRAILER): assets/gpw2019-sponsors.png
	# -v must come from the video, sample_rate as well
	ffmpeg -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=$(AUDIO_SAMPLE_RATE)" \
		-loop 1 -framerate $(RATE) -i $< -s $(TARGET_RESOLUTION) \
		-c:v libx264 -pix_fmt yuv420p -c:a aac -b:a $(AUDIO_RATE) -t $(DURATION) $@ -y

%.joined.mkv: %.[1234].mkv
	$(JOIN) $(sort $^) -o $@

%.trimmed.mkv: %.joined.mkv %.yml
	$(TRIM) $^ -o $@

%.middle.mkv: %.trimmed.mkv %.yml
	$(STAMP) --framerate $(RATE) --x 569 --y 786 assets/sponsors-fix.png $^ -o $@

#%.start.mkv: %.trimmed.mkv
	#$(TRIM) $^ --start 00:00:00 --end 00:01:00 -o $@

#%.end.mkv: %.trimmed.mkv
	#$(TRIM) $^ --start -00:01:00 --end -00:00:00 -o $@

#%.final.MP4: $(HEADER) %.inset-start.MP4 %.middle.MP4 %.inset-end.MP4 $(TRAILER) %.yml
%.final.mkv: $(HEADER) %.middle.mkv $(TRAILER) %.yml
	$(JOIN) $^ -o $@
