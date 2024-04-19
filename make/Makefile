CONFIG ?= cfg/gpw2021.cfg

# Find rate of recorded video
# ffprobe 2019-03-07-what-i-learned-about-sql-in-2018.joined.MP4 -select_streams v:0 -show_entries stream=r_frame_rate -of compact=p=0:nk=1
#RATE=25
#RATE=29.97
#RATE=30000/1001

# Find timestamp offsets of sound and video in a stream:
# ffprobe -v error -show_streams <file> | egrep 'start_pts|start_time'
# ideally you should have both at 0 :)

# ffprobe -v 0 -of csv=p=0 -select_streams v:0 -show_entries stream=r_frame_rate
RATE=25/1

AUDIO_RATE=256k

# ffprobe -v 0 -of csv=p=0 -select_streams a:0 -show_entries stream=sample_rate
AUDIO_SAMPLE_RATE ?= 44100
# ffprobe -v error -select_streams v:0 -show_entries stream=height,width -of csv=s=x:p=0

VIDEO=video

include $(CONFIG)

FFMPEG ?= $(which ffmpeg)
$(info Using ffmpeg from $(FFMPEG))
FFPROBE ?= $(which ffprobe)
VF_SCALE ?= scale
X264 ?= libx264
TARGET_RESOLUTION ?= 1920x1080
DURATION_HEADER ?=10
DURATION_TRAILER ?=75

INPUT_VIDEOS := $(wildcard $(VIDEO)/*.1.mkv)
METADATA_FILES := $(subst .1.mkv,.yml,$(INPUT_VIDEOS))
VIDEOS := $(subst .yml,.final.mkv,$(wildcard $(VIDEO)/*.yml))
TRAILER_ASSETS := $(shell perl -nle 'print "assets/$$1" if /file\s+.(.*?).$$/' $(TRAILER_SLIDESHOW))

.PRECIOUS: %.yml %.middle.mkv
.PHONY: prepare-cut videos trailer-assets

metadata: $(METADATA_FILES)

prepare-cut: $(INPUT_VIDEOS) metadata

videos: $(VIDEOS)

trailer-assets: $(TRAILER_ASSETS)

%.png: %.svg
	inkscape --export-type=png --export-area-page -d 25.40 $< -o $@

#%.yml : | %.joined.mkv
%.yml : %.1.mkv
	$(METADATA) $^ $| --show "$(SHOW)" --language deu --url-base "$(ACT_BASE)" -o $@

$(TRAILER_SLIDESHOW): trailer-assets

$(TRAILER): trailer-assets $(TRAILER_SLIDESHOW)
	# -v must come from the video, sample_rate as well
	#		-s "$(TARGET_RESOLUTION)" \
	echo Audio sample rate $(AUDIO_SAMPLE_RATE)
	$(FFMPEG) \
	$(FFMPEG_OPT) \
		-f concat -i $(TRAILER_SLIDESHOW) \
		-f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=$(AUDIO_SAMPLE_RATE)" \
		-vf $(VF_SCALE)=$(TARGET_RESOLUTION),fps=25 \
		-c:v $(X264) -pix_fmt yuv420p \
		-c:a aac -b:a $(AUDIO_RATE) -t $(DURATION_TRAILER) \
		$@ -y

#$(HEADER): $(HEADER_ASSETS)
#	# -v must come from the video, sample_rate as well
#	ffmpeg -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=$(AUDIO_SAMPLE_RATE)" \
#		-loop 1 -framerate $(RATE) -i $< -s $(TARGET_RESOLUTION) \
#		-c:v $(X264) -pix_fmt yuv420p -c:a aac -b:a $(AUDIO_RATE) -t $(DURATION_HEADER) $@ -y

%.titlecard.svg: %.yml $(TITLECARD)
	$(TITLEGEN) --template $(TITLECARD) --config $< -o $@

%.titlecard.png: %.titlecard.svg $(TITLECARD)

%.titlecard.mkv: %.titlecard.png $(TITLECARD)
	# Titlecard animieren
	$(FFMPEG) \
	$(FFMPEG_OPT) \
		-i $< \
		-loop 1 -framerate $(RATE) -i $< \
		-f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=$(AUDIO_SAMPLE_RATE)" \
		-vf $(VF_SCALE)=$(TARGET_RESOLUTION),fps=25 \
	    -video_size $(TARGET_RESOLUTION) \
		-c:v $(X264) -pix_fmt yuv420p \
		-c:a aac -b:a $(AUDIO_RATE) -t 5 \
		$@ -y

%.title.mkv: %.titlecard.mkv $(ANIMATED_TITLE)
	$(JOIN) $(ANIMATED_TITLE) $< -o $@

# The filenames for the cutlist come from the YAML file now
%.middle.mkv: %.yml %.[1234].mkv
	$(CUTLIST) $< -o $@

#%.final.MP4: $(HEADER) %.inset-start.MP4 %.middle.MP4 %.inset-end.MP4 $(TRAILER) %.yml
%.final.mkv: %.title.mkv %.middle.mkv $(TRAILER) %.yml
	$(JOIN) $^ -o $@
