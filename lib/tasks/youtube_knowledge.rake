# frozen_string_literal: true

namespace :youtube do
  namespace :knowledge do
    desc "Extract transcripts for all videos (with timestamps)"
    task :extract_transcripts, [ :limit ] => :environment do |_t, args|
      limit = args[:limit]&.to_i

      puts "=" * 50
      puts "Extracting transcripts with timestamps"
      puts "=" * 50

      scope = YoutubeVideo.where(transcript: [ nil, "" ])
      scope = scope.limit(limit) if limit

      total = scope.count
      puts "Videos without transcript: #{total}"

      if total == 0
        puts "All videos already have transcripts!"
        exit 0
      end

      success = 0
      failed = 0
      no_subs = 0

      scope.find_each.with_index do |video, index|
        language = video.youtube_channel&.language || "ko"
        print "[#{index + 1}/#{total}] [#{language}] #{video.title[0..35]}... "

        begin
          structured = YoutubeChannelScraper.extract_structured_subtitles(video.youtube_url, language: language)

          if structured.present?
            transcript = YoutubeChannelScraper.format_transcript(structured)
            video.update!(transcript: transcript, structured_transcript: structured)
            puts "OK (#{transcript.length} chars, #{structured.length} captions)"
            success += 1
          else
            transcript = YoutubeChannelScraper.extract_subtitles(video.youtube_url, language: language)
            if transcript.present?
              video.update!(transcript: transcript)
              puts "OK flat (#{transcript.length} chars)"
              success += 1
            else
              puts "no subs"
              no_subs += 1
            end
          end
        rescue => e
          puts "✗ (#{e.message[0..30]})"
          failed += 1
        end

        # Rate limiting to avoid being blocked (5 seconds for safety)
        sleep 5
      end

      puts
      puts "=" * 50
      puts "Results:"
      puts "  Success: #{success}"
      puts "  No subtitles: #{no_subs}"
      puts "  Failed: #{failed}"
      puts "=" * 50
    end

    desc "Show transcript extraction status"
    task transcript_stats: :environment do
      total = YoutubeVideo.count
      with_transcript = YoutubeVideo.where.not(transcript: [ nil, "" ]).count
      without_transcript = total - with_transcript

      puts "\n📊 Transcript Status:"
      puts "  Total videos: #{total}"
      puts "  With transcript: #{with_transcript} (#{(with_transcript.to_f / total * 100).round(1)}%)"
      puts "  Without transcript: #{without_transcript}"

      if with_transcript > 0
        avg_length = YoutubeVideo.where.not(transcript: [ nil, "" ]).average("LENGTH(transcript)").to_i
        puts "  Average transcript length: #{avg_length} chars"
      end
    end

    desc "Seed YouTube channels from configuration"
    task seed_channels: :environment do
      puts "Seeding YouTube channels..."
      YoutubeChannel.seed_configured_channels!
      puts "Done! #{YoutubeChannel.count} channels configured."

      YoutubeChannel.all.each do |channel|
        puts "  - #{channel.name} (@#{channel.handle})"
      end
    end

    desc "Sync videos from all active YouTube channels (requires yt-dlp)"
    task sync: :environment do
      puts "Syncing videos from YouTube channels..."

      YoutubeChannel.active.find_each do |channel|
        puts "  Syncing #{channel.name}..."
        count = YoutubeSyncService.sync_channel(channel)
        puts "    -> #{count} videos"
      rescue => e
        puts "    -> Error: #{e.message}"
      end

      puts "Done!"
    end

    desc "Analyze videos with Claude AI (requires transcript)"
    task :analyze, [ :limit ] => :environment do |_t, args|
      limit = (args[:limit] || 10).to_i

      unless YoutubeKnowledgeExtractionService.configured?
        puts "Error: ANTHROPIC_API_KEY is not configured"
        exit 1
      end

      # Only analyze videos that have transcripts
      videos = YoutubeVideo
        .where(analysis_status: "pending")
        .where.not(transcript: [ nil, "" ])
        .limit(limit)

      total = videos.count
      puts "Analyzing #{total} videos with transcripts (limit: #{limit})..."

      if total == 0
        puts "No videos with transcripts pending analysis."
        puts "Run 'rails youtube:knowledge:extract_transcripts' first."
        exit 0
      end

      analyzed = 0
      failed = 0

      videos.find_each do |video|
        print "  Analyzing: #{video.title[0..50]}... "
        YoutubeKnowledgeExtractionService.analyze_video(video)
        puts "✓ (#{video.fitness_knowledge_chunks.count} chunks)"
        analyzed += 1
      rescue => e
        puts "✗ #{e.message[0..50]}"
        failed += 1
      end

      puts "\nDone! #{analyzed} analyzed, #{failed} failed"
    end

    desc "Generate embeddings for knowledge chunks"
    task :embed, [ :limit ] => :environment do |_t, args|
      limit = (args[:limit] || 100).to_i

      unless EmbeddingService.pgvector_available?
        puts "pgvector not available - skipping"
        exit 0
      end

      unless EmbeddingService.configured?
        puts "Error: OPENAI_API_KEY is not configured"
        exit 1
      end

      puts "Generating embeddings (limit: #{limit})..."
      EmbeddingService.embed_all_pending_chunks(limit: limit)
      puts "Done!"
    end

    desc "Run full knowledge collection: sync → extract transcripts → analyze → embed"
    task :collect, [ :analyze_limit ] => :environment do |_t, args|
      analyze_limit = (args[:analyze_limit] || 50).to_i

      puts "=" * 50
      puts "YouTube Knowledge Collection"
      puts "=" * 50

      # 1. Seed channels
      Rake::Task["youtube:knowledge:seed_channels"].invoke

      # 2. Sync videos
      puts "\n"
      Rake::Task["youtube:knowledge:sync"].invoke

      # 3. Extract transcripts (NEW STEP)
      puts "\n"
      Rake::Task["youtube:knowledge:extract_transcripts"].invoke(analyze_limit)

      # 4. Analyze with Claude
      puts "\n"
      Rake::Task["youtube:knowledge:analyze"].invoke(analyze_limit)

      # 4.5. Extract clips (NEW)
      puts "\n"
      Rake::Task["youtube:knowledge:extract_clips"].invoke(analyze_limit)

      # 5. Embed
      puts "\n"
      Rake::Task["youtube:knowledge:embed"].invoke

      # 6. Link clips
      puts "\n"
      Rake::Task["youtube:knowledge:link_clips"].invoke

      puts "\n" + "=" * 50
      puts "Collection complete!"
      Rake::Task["youtube:knowledge:stats"].invoke
    end

    desc "Backfill structured transcripts for videos that have flat transcript but no structured"
    task :backfill_structured_transcripts, [ :limit ] => :environment do |_t, args|
      limit = args[:limit]&.to_i

      puts "=" * 50
      puts "Backfilling structured transcripts"
      puts "=" * 50

      scope = YoutubeVideo.where.not(transcript: [ nil, "" ])
                          .where(structured_transcript: nil)
      scope = scope.limit(limit) if limit

      total = scope.count
      puts "Videos needing structured transcript: #{total}"

      if total == 0
        puts "All videos already have structured transcripts!"
        next
      end

      success = 0
      failed = 0
      no_subs = 0

      scope.find_each.with_index do |video, index|
        language = video.youtube_channel&.language || "ko"
        print "[#{index + 1}/#{total}] [#{language}] #{video.title[0..35]}... "

        begin
          structured = YoutubeChannelScraper.extract_structured_subtitles(video.youtube_url, language: language)

          if structured.present?
            video.update!(structured_transcript: structured)
            puts "OK (#{structured.length} captions)"
            success += 1
          else
            puts "no captions"
            no_subs += 1
          end
        rescue => e
          puts "FAIL (#{e.message[0..30]})"
          failed += 1
        end

        sleep 3
      end

      puts
      puts "=" * 50
      puts "Results: success=#{success}, no_subs=#{no_subs}, failed=#{failed}"
      puts "=" * 50
    end

    desc "Extract exercise video clips from structured transcripts using Claude"
    task :extract_clips, [ :limit ] => :environment do |_t, args|
      limit = (args[:limit] || 50).to_i

      puts "=" * 50
      puts "Extracting exercise video clips"
      puts "=" * 50

      videos = YoutubeVideo
        .where.not(structured_transcript: nil)
        .left_joins(:exercise_video_clips)
        .where(exercise_video_clips: { id: nil })
        .limit(limit)
        .order(:id)

      total = videos.count
      puts "Videos to process: #{total} (limit: #{limit})"

      if total == 0
        puts "No videos need clip extraction!"
        next
      end

      success = 0
      failed = 0
      total_clips = 0

      videos.find_each.with_index do |video, index|
        print "[#{index + 1}/#{total}] #{video.title[0..40]}... "

        begin
          clips = ExerciseClipExtractionService.extract(video)
          puts "OK (#{clips.length} clips)"
          success += 1
          total_clips += clips.length
        rescue => e
          puts "FAIL (#{e.message[0..40]})"
          failed += 1
        end
      end

      puts
      puts "=" * 50
      puts "Results: success=#{success}, failed=#{failed}, total_clips=#{total_clips}"
      puts "=" * 50
    end

    desc "Link exercise video clips to Exercise records by english_name matching"
    task link_clips: :environment do
      puts "Linking exercise video clips to Exercise records..."

      unlinked = ExerciseVideoClip.where(exercise_id: nil)
      total = unlinked.count
      linked = 0

      unlinked.find_each do |clip|
        exercise = Exercise.find_by(english_name: clip.exercise_name)
        if exercise
          clip.update!(exercise_id: exercise.id)
          linked += 1
        end
      end

      puts "Done! Linked #{linked}/#{total} clips"
    end

    desc "Show exercise video clip statistics"
    task clip_stats: :environment do
      total = ExerciseVideoClip.count
      puts "\nExercise Video Clip Statistics:"
      puts "  Total clips: #{total}"

      if total > 0
        puts "  By type:"
        ExerciseVideoClip.group(:clip_type).count.each do |type, count|
          puts "    #{type}: #{count}"
        end

        puts "  By language:"
        ExerciseVideoClip.group(:source_language).count.each do |lang, count|
          puts "    #{lang}: #{count}"
        end

        puts "  Unique exercises: #{ExerciseVideoClip.distinct.count(:exercise_name)}"
        puts "  Linked to Exercise: #{ExerciseVideoClip.where.not(exercise_id: nil).count}"
        puts "  Unlinked: #{ExerciseVideoClip.where(exercise_id: nil).count}"

        puts "  Videos with clips: #{ExerciseVideoClip.distinct.count(:youtube_video_id)}"
        puts "  Videos with structured_transcript: #{YoutubeVideo.where.not(structured_transcript: nil).count}"
      end
    end

    desc "Test clip extraction on a single YouTube URL"
    task :test_clip, [ :url, :language ] => :environment do |_t, args|
      url = args[:url]
      language = args[:language] || "ko"

      unless url
        puts "Usage: rails youtube:knowledge:test_clip[URL,language]"
        next
      end

      puts "Extracting structured transcript from: #{url}"
      puts "Language: #{language}"
      puts "-" * 50

      structured = YoutubeChannelScraper.extract_structured_subtitles(url, language: language)

      if structured.blank?
        puts "No subtitles available!"
        next
      end

      puts "Captions: #{structured.length}"
      puts "First 5 captions:"
      structured.first(5).each_with_index do |cap, i|
        puts "  [#{i}] #{cap['start']}s: #{cap['text']}"
      end

      # Find or create temporary video record
      video_id = url[/[?&]v=([^&]+)/, 1] || url.split("/").last
      video = YoutubeVideo.find_by(video_id: video_id)

      unless video
        puts "\nVideo not in DB. Creating temporary record..."
        channel = YoutubeChannel.first
        unless channel
          puts "No YouTube channel in DB. Cannot create temporary video."
          next
        end
        video = YoutubeVideo.create!(
          video_id: video_id,
          title: "Test video",
          youtube_channel: channel,
          structured_transcript: structured,
          transcript: YoutubeChannelScraper.format_transcript(structured)
        )
      end

      video.update!(structured_transcript: structured) if video.structured_transcript.blank?

      puts "\nExtracting clips with Claude..."
      clips = ExerciseClipExtractionService.extract(video)

      puts "\nExtracted #{clips.length} clips:"
      clips.each_with_index do |clip, i|
        puts "\n#{i + 1}. [#{clip.clip_type}] #{clip.title}"
        puts "   Exercise: #{clip.exercise_name} (#{clip.muscle_group})"
        puts "   Time: #{clip.timestamp_start.round(1)}s - #{clip.timestamp_end.round(1)}s"
        puts "   URL: #{clip.video_url_with_timestamp}"
        puts "   Summary: #{clip.summary}"
        puts "   Content: #{clip.content[0..150]}..."
      end
    end

    desc "Show knowledge statistics"
    task stats: :environment do
      puts "\n📊 Statistics:"
      puts "  Channels: #{YoutubeChannel.count} (#{YoutubeChannel.active.count} active)"
      puts "  Videos: #{YoutubeVideo.count} total"
      puts "    - Pending: #{YoutubeVideo.pending.count}"
      puts "    - Analyzed: #{YoutubeVideo.completed.count}"
      puts "    - Failed: #{YoutubeVideo.failed.count}"
      puts "  Knowledge chunks: #{FitnessKnowledgeChunk.count}"
    end

    desc "Reanalyze all videos with Claude (requires transcripts)"
    task reanalyze_all: :environment do
      unless YoutubeKnowledgeExtractionService.configured?
        puts "Error: ANTHROPIC_API_KEY is not configured"
        exit 1
      end

      # Only reanalyze videos that have transcripts
      videos = YoutubeVideo.where.not(transcript: [ nil, "" ])
      total = videos.count

      puts "=" * 50
      puts "Reanalyzing #{total} videos with Claude"
      puts "=" * 50

      videos.find_each.with_index do |video, index|
        ReanalyzeVideoJob.perform_async(video.id)
        print "." if (index + 1) % 100 == 0
      end

      puts "\n\n✓ Enqueued #{total} reanalysis jobs"
      puts "Monitor progress with: rails youtube:knowledge:stats"
    end

    desc "Reanalyze specific number of videos (for testing)"
    task :reanalyze, [ :limit ] => :environment do |_t, args|
      limit = (args[:limit] || 10).to_i

      unless YoutubeKnowledgeExtractionService.configured?
        puts "Error: ANTHROPIC_API_KEY is not configured"
        exit 1
      end

      videos = YoutubeVideo.where.not(transcript: [ nil, "" ]).limit(limit)

      puts "Enqueueing #{videos.count} videos for reanalysis..."

      videos.find_each do |video|
        ReanalyzeVideoJob.perform_async(video.id)
        puts "  Enqueued: #{video.title[0..50]}"
      end

      puts "\n✓ Done! Monitor with: rails youtube:knowledge:stats"
    end

    desc "Test analyze a single YouTube URL"
    task :test_url, [ :url, :language ] => :environment do |_t, args|
      url = args[:url]
      language = args[:language] || "ko"

      unless url
        puts "Usage: rails youtube:knowledge:test_url[URL,language]"
        puts "  language: 'ko' (Korean, default) or 'en' (English)"
        puts "Example: rails youtube:knowledge:test_url[https://www.youtube.com/watch?v=xxx,en]"
        exit 1
      end

      unless YoutubeKnowledgeExtractionService.configured?
        puts "Error: ANTHROPIC_API_KEY is not configured"
        exit 1
      end

      puts "Extracting transcript from: #{url}"
      puts "Language: #{language}"
      puts "-" * 50

      transcript = YoutubeChannelScraper.extract_subtitles(url, language: language)

      if transcript.blank?
        puts "No subtitles available for this video."
        exit 1
      end

      puts "Transcript length: #{transcript.length} chars"
      puts "First 500 chars:"
      puts transcript[0..500]
      puts "\n" + "-" * 50

      puts "\nAnalyzing with Claude (language: #{language})..."
      result = YoutubeKnowledgeExtractionService.analyze_transcript(transcript, language: language)

      puts "Category: #{result[:category]}"
      puts "Difficulty: #{result[:difficulty_level]}"
      puts "Summary: #{result[:summary]}"
      puts "\nKnowledge Chunks (#{result[:knowledge_chunks]&.count || 0}):"

      result[:knowledge_chunks]&.each_with_index do |chunk, i|
        puts "\n#{i + 1}. [#{chunk[:type]}] #{chunk[:summary]}"
        puts "   Exercise: #{chunk[:exercise_name]}" if chunk[:exercise_name]
        puts "   Muscle: #{chunk[:muscle_group]}" if chunk[:muscle_group]
        timestamp = if chunk[:timestamp_start]
          "[#{chunk[:timestamp_start]}s - #{chunk[:timestamp_end]}s]"
        else
          "[NO TIMESTAMP ⚠️]"
        end
        puts "   Timestamp: #{timestamp}"
        puts "   Content (KO): #{chunk[:content][0..200]}..."
        if chunk[:content_original]
          puts "   Content (EN): #{chunk[:content_original][0..200]}..."
        end
      end
    end

    desc "Show timestamp statistics"
    task timestamp_stats: :environment do
      total = FitnessKnowledgeChunk.count
      with_ts = FitnessKnowledgeChunk.where.not(timestamp_start: nil).count
      without_ts = total - with_ts

      puts "\n📊 Timestamp Statistics:"
      puts "  Total chunks: #{total}"
      puts "  With timestamps: #{with_ts} (#{(with_ts.to_f / total * 100).round(1)}%)"
      puts "  Without timestamps: #{without_ts} (#{(without_ts.to_f / total * 100).round(1)}%)"
    end
  end
end
