# frozen_string_literal: true

namespace :youtube do
  namespace :knowledge do
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

    desc "Analyze pending videos with Gemini AI"
    task :analyze, [:limit] => :environment do |_t, args|
      limit = (args[:limit] || 10).to_i

      unless GeminiConfig.configured?
        puts "Error: GEMINI_API_KEY is not configured"
        exit 1
      end

      puts "Analyzing pending videos (limit: #{limit})..."

      analyzed = 0
      failed = 0

      YoutubeVideo.pending.limit(limit).find_each do |video|
        print "  Analyzing: #{video.title[0..50]}... "
        YoutubeKnowledgeExtractionService.analyze_video(video)
        puts "✓ (#{video.fitness_knowledge_chunks.count} chunks)"
        analyzed += 1
      rescue => e
        puts "✗ #{e.message}"
        failed += 1
      end

      puts "\nDone! #{analyzed} analyzed, #{failed} failed"
    end

    desc "Generate embeddings for knowledge chunks"
    task :embed, [:limit] => :environment do |_t, args|
      limit = (args[:limit] || 100).to_i

      unless EmbeddingService.pgvector_available?
        puts "pgvector not available - skipping"
        exit 0
      end

      unless EmbeddingService.configured?
        puts "Error: GEMINI_API_KEY is not configured"
        exit 1
      end

      puts "Generating embeddings (limit: #{limit})..."
      EmbeddingService.embed_all_pending_chunks(limit: limit)
      puts "Done!"
    end

    desc "Run full knowledge collection: sync → analyze → embed"
    task :collect, [:analyze_limit] => :environment do |_t, args|
      analyze_limit = (args[:analyze_limit] || 50).to_i

      puts "=" * 50
      puts "YouTube Knowledge Collection"
      puts "=" * 50

      # 1. Seed channels
      Rake::Task["youtube:knowledge:seed_channels"].invoke

      # 2. Sync videos
      puts "\n"
      Rake::Task["youtube:knowledge:sync"].invoke

      # 3. Analyze
      puts "\n"
      Rake::Task["youtube:knowledge:analyze"].invoke(analyze_limit)

      # 4. Embed
      puts "\n"
      Rake::Task["youtube:knowledge:embed"].invoke

      puts "\n" + "=" * 50
      puts "Collection complete!"
      Rake::Task["youtube:knowledge:stats"].invoke
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

    desc "Analyze a single YouTube URL (test)"
    task :test_url, [:url] => :environment do |_t, args|
      url = args[:url]

      unless url
        puts "Usage: rails youtube:knowledge:test_url[https://www.youtube.com/watch?v=VIDEO_ID]"
        exit 1
      end

      unless GeminiConfig.configured?
        puts "Error: GEMINI_API_KEY is not configured"
        exit 1
      end

      puts "Analyzing: #{url}"
      puts "-" * 50

      result = YoutubeKnowledgeExtractionService.analyze_url(url)

      puts "Title: #{result[:title]}"
      puts "Category: #{result[:category]}"
      puts "Difficulty: #{result[:difficulty_level]}"
      puts "Summary: #{result[:summary]}"
      puts "\nKnowledge Chunks (#{result[:knowledge_chunks]&.count || 0}):"

      result[:knowledge_chunks]&.each_with_index do |chunk, i|
        puts "\n#{i + 1}. [#{chunk[:type]}] #{chunk[:summary]}"
        puts "   Exercise: #{chunk[:exercise_name]}" if chunk[:exercise_name]
        puts "   Muscle: #{chunk[:muscle_group]}" if chunk[:muscle_group]
        puts "   Content: #{chunk[:content][0..200]}..."
      end
    end
  end
end
