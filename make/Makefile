CONFIG ?= cfg/gpw2021.cfg

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
DURATION_HEADER=5
DURATION_TRAILER=30

VIDEO=video

include $(CONFIG)

JOINED_VIDEOS := $(subst .1.mkv,.joined.mkv,$(wildcard $(VIDEO)/*.1.mkv))
VIDEOS := $(subst .joined.mkv,.final.mkv,$(wildcard $(VIDEO)/*.joined.mkv))
METADATA_FILES := $(subst .joined.mkv,.yml,$(JOINED_VIDEOS))

.PRECIOUS: %.yml %.middle.mkv
.PHONY: prepare-cut videos

metadata: $(METADATA_FILES)

prepare-cut: $(JOINED_VIDEOS) metadata

videos: $(VIDEOS)

%.png: %.svg
	inkscape --export-type=png -d 25.40 $< -o $@

%.yml : | %.joined.mkv
	$(METADATA) $^ $| --show "$(SHOW)" --language deu -o $@

$(TRAILER): $(TRAILER_ASSETS) $(TRAILER_SLIDESHOW)
	# -v must come from the video, sample_rate as well
	#		-s "$(TARGET_RESOLUTION)" \
	ffmpeg \
		-f concat -i $(TRAILER_SLIDESHOW) \
		-f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=$(AUDIO_SAMPLE_RATE)" \
		-vf scale=$(TARGET_RESOLUTION),fps=25 \
		-c:v libx264 -pix_fmt yuv420p -c:a aac -b:a $(AUDIO_RATE) -t $(DURATION_TRAILER) \
		$@ -y

#$(HEADER): $(HEADER_ASSETS)
#	# -v must come from the video, sample_rate as well
#	ffmpeg -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=$(AUDIO_SAMPLE_RATE)" \
#		-loop 1 -framerate $(RATE) -i $< -s $(TARGET_RESOLUTION) \
#		-c:v libx264 -pix_fmt yuv420p -c:a aac -b:a $(AUDIO_RATE) -t $(DURATION_HEADER) $@ -y

%.title.svg: %.yml
	$(TITLEGEN) --template $(TITLECARD) --config $< -o $@

%.title.png: %.title.svg

%.title.mkv: %.title.png
	# -v must come from the video, sample_rate as well
	#ffmpeg -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=$(AUDIO_SAMPLE_RATE)" \
	#	-loop 1 -framerate $(RATE) -i $< -s $(TARGET_RESOLUTION) \
	#	-c:v libx264 -pix_fmt yuv420p -c:a aac -b:a $(AUDIO_RATE) -t $(DURATION_HEADER) $@ -y
	ffmpeg -i $(ANIMATED_TITLE) \
	       -i $< \
		   -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=$(AUDIO_SAMPLE_RATE)" \
	       -filter_complex "[1]format=argb,geq=r='r(X,Y)':a='0.5*alpha(X,Y)'[b];[0:v][b] overlay" -s $(TARGET_RESOLUTION) \
	       -r $(RATE) \
	       -t 4 \
	       -c:a aac \
	       -c:v libx264 -pix_fmt yuv420p \
	       "$@" -y

%.joined.mkv: %.[1234].mkv
	$(JOIN) $(sort $^) -o $@

%.trimmed.mkv: %.joined.mkv %.yml
	$(TRIM) $^ -o $@

%.middle.mkv: %.trimmed.mkv %.yml
	cp $< $@

#%.start.mkv: %.trimmed.mkv
	#$(TRIM) $^ --start 00:00:00 --end 00:01:00 -o $@

#%.end.mkv: %.trimmed.mkv
	#$(TRIM) $^ --start -00:01:00 --end -00:00:00 -o $@

#%.final.MP4: $(HEADER) %.inset-start.MP4 %.middle.MP4 %.inset-end.MP4 $(TRAILER) %.yml
%.final.mkv: %.title.mkv %.middle.mkv $(TRAILER) %.yml
	$(JOIN) $^ -o $@
