# frozen_string_literal: true

module PaperTrail
  # mongo_trails captures paper_trail state on the saved instance via after_save (see
  # ModelConfig#paper_trail_accumulate_versions): the accumulated field changes plus a snapshot
  # of the whole PaperTrail.request context. It reads that state back from after_commit to build
  # the version.
  #
  # When the same record is saved more than once in a transaction through different in-memory
  # instances, Rails 7.1+ picks ONE instance to fire after_commit on and discards the rest — so
  # any state captured on the discarded instances is lost.
  #
  # Rails' built-in fix propagates `_new_record_before_last_commit` from the earlier candidate
  # to the later one (active_record/connection_adapters/abstract/transaction.rb). We mirror that
  # for paper_trail state, in the opposite direction: when
  # `run_commit_callbacks_on_first_saved_instances_in_transaction = true` causes Rails to KEEP
  # the earlier candidate and DROP later instances, we:
  #
  #   * merge every discarded instance's accumulated field changes onto the kept candidate, and
  #   * hand the kept candidate the captured request context of the LAST writer.
  #
  # The request context is NOT taken from "whichever instance was enrolled in the transaction
  # last": instances are enrolled in first-save order, so when the kept (first) instance is
  # itself re-saved AFTER a later instance, naively copying the later instance's state would
  # clobber the kept instance's own, newer state and attribute the version to the wrong writer
  # (e.g. the wrong automation). Instead we read the full, chronologically-ordered list of saves
  # to find the genuinely LAST writer of each record. The context itself is opaque here: the
  # model (ModelConfig) owns what is captured and restored, so this code stays agnostic of any
  # host-app-specific request state.
  module CallbackPropagation
    private

    def prepare_instances_to_run_callbacks_on(records)
      # `records` here is the de-duplicated list Rails passes in (`unique_records`). The full,
      # ordered list of saves is `self.records`: a record saved through several in-memory
      # instances — or the same instance re-saved — appears once per save, in chronological
      # order. We use it to find the instance that performed the LAST save of each record, so
      # the version is attributed to it rather than to whichever instance happened to be
      # enrolled in the transaction last.
      records.each_with_object({}) do |record, candidates|
        next unless record.trigger_transactional_callbacks?
        earlier_saved_candidate = candidates[record]
        merge_accumulated_versions(from: record) if @state.committed?
        next if earlier_saved_candidate && record.class.run_commit_callbacks_on_first_saved_instances_in_transaction
        next if earlier_saved_candidate&.destroyed? && !record.destroyed?
        record._new_record_before_last_commit = true if earlier_saved_candidate&._new_record_before_last_commit
        candidates[record] = record
      end
    end

    # Build { record => last_saved_instance } honouring chronological save order. Later entries
    # overwrite earlier ones, so the final value is the instance that saved the record last.
    def last_writer_by_record(all_saves)
      return {} unless all_saves

      all_saves.each_with_object({}) do |record, acc|
        next unless record.respond_to?(:paper_trail_captured_state, true)

        acc[record] = record
      end
    end

    def adopt_last_writer_state(into:, from:)
      return if from.nil? || from.equal?(into)
      return unless from.respond_to?(:paper_trail_captured_state, true) && into.respond_to?(:paper_trail_adopt_state, true)

      into.send(:paper_trail_adopt_state, from.send(:paper_trail_captured_state))
    end

    def merge_accumulated_versions(from:)
      return unless from.respond_to?(:paper_trail_accumulated_versions)

      from_changes = from.paper_trail_accumulated_versions
      return if from_changes.blank?

      from.send(:paper_trail_within_writer_request) do
        if from.previously_new_record?
          from.paper_trail.record_create if from.paper_trail.save_version?
        else
          from.paper_trail.record_update(force: false, in_after_callback: true, is_touch: false) if from.paper_trail.save_version? # rubocop:disable Style/IfUnlessModifier,Layout/LineLength
        end
      end
    end
  end
end

ActiveSupport.on_load(:active_record) do
  require 'active_record/connection_adapters/abstract/transaction'

  # `prepare_instances_to_run_callbacks_on` and the
  # `run_commit_callbacks_on_first_saved_instances_in_transaction` class attribute were
  # introduced together in Rails 7.1. On older Rails the dedup logic is inline in
  # `commit_records` and not configurable — skip the prepend so we don't shadow a method
  # the gem doesn't need and don't reference a missing class attribute.
  if ActiveRecord::ConnectionAdapters::Transaction.private_method_defined?(:prepare_instances_to_run_callbacks_on)
    ActiveRecord::ConnectionAdapters::Transaction.prepend(PaperTrail::CallbackPropagation)
  end
end
