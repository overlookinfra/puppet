# frozen_string_literal: true

require_relative '../../puppet/indirector/face'

Puppet::Indirector::Face.define(:catalog, '0.0.1') do
  copyright "Puppet Inc., Vox Pupuli", 2011
  license   "Apache 2 license; see COPYING"

  summary _("Compile, save, view, and convert catalogs.")
  description <<-'EOT'
    This subcommand deals with catalogs, which are compiled per-node artifacts
    generated from a set of Puppet manifests. By default, it interacts with the
    compiling subsystem and compiles a catalog using the default manifest and
    `certname`, but you can change the source of the catalog with the
    `--terminus` option. You can also choose to print any catalog in 'dot'
    format (for easy graph viewing with OmniGraffle or Graphviz) with
    '--render-as dot'.
  EOT
  short_description <<-'EOT'
    This subcommand deals with catalogs, which are compiled per-node artifacts
    generated from a set of Puppet manifests. By default, it interacts with the
    compiling subsystem and compiles a catalog using the default manifest and
    `certname`; use the `--terminus` option to change the source of the catalog.
  EOT

  deactivate_action(:destroy)
  deactivate_action(:search)
  action(:find) do
    summary _("Retrieve the catalog for the node from which the command is run.")
    arguments "<certname>, <facts>"
    option("--facts_for_catalog") do
      summary _("Not implemented for the CLI; facts are collected internally.")
    end
    returns <<-'EOT'
      A serialized catalog. When used from the Ruby API, returns a
      Puppet::Resource::Catalog object.
    EOT

    when_invoked do |*args|
      # Default the key to Puppet[:certname] if none is supplied
      if args.length == 1
        key = Puppet[:certname]
      else
        key = args.shift
      end
      call_indirection_method :find, key, args.first
    end
  end

  action(:apply) do
    summary "Find and apply a catalog."
    description <<-'EOT'
      Finds and applies a catalog. This action takes no arguments, but
      the source of the catalog can be managed with the `--terminus` option.
    EOT
    returns <<-'EOT'
      Nothing. When used from the Ruby API, returns a
      Puppet::Transaction::Report object.
    EOT
    examples <<-'EOT'
      Apply the locally cached catalog:

      $ puppet catalog apply --terminus yaml

      Retrieve a catalog from the master and apply it, in one step:

      $ puppet catalog apply --terminus rest

      API example:

          # ...
          Puppet::Face[:catalog, '0.0.1'].download
          # (Termini are singletons; catalog.download has a side effect of
          # setting the catalog terminus to yaml)
          report  = Puppet::Face[:catalog, '0.0.1'].apply
          # ...
    EOT

    when_invoked do |_options|
      catalog = Puppet::Face[:catalog, "0.0.1"].find(Puppet[:certname]) or raise "Could not find catalog for #{Puppet[:certname]}"
      catalog = catalog.to_ral

      report = Puppet::Transaction::Report.new
      report.configuration_version = catalog.version
      report.environment = Puppet[:environment]

      Puppet::Util::Log.newdestination(report)

      begin
        benchmark(:notice, "Finished catalog run in %{seconds} seconds") do
          catalog.apply(:report => report)
        end
      rescue => detail
        Puppet.log_exception(detail, "Failed to apply catalog: #{detail}")
      end

      report.finalize_report
      report
    end
  end

  action(:compile) do
    summary _("Compile a catalog.")
    description <<-'EOT'
      Compiles a catalog locally for a node, requiring access to modules, node classifier, etc.
    EOT
    examples <<-'EOT'
      Compile catalog for node 'mynode':

      $ puppet catalog compile mynode --codedir ...
    EOT
    returns <<-'EOT'
      A serialized catalog.
    EOT
    when_invoked do |*args|
      Puppet.settings.preferred_run_mode = :server
      Puppet::Face[:catalog, :current].find(*args)
    end
  end

  action(:download) do
    summary "Download this node's catalog from the puppet master server."
    description <<-'EOT'
      Retrieves a catalog from the puppet master and saves it to the local yaml
      cache. This action always contacts the puppet master and will ignore
      alternate termini.

      The saved catalog can be used in any subsequent catalog action by specifying
      '--terminus yaml' for that action.
    EOT
    returns "Nothing."
    notes <<-'EOT'
      When used from the Ruby API, this action has a side effect of leaving
      Puppet::Resource::Catalog.indirection.terminus_class set to yaml. The
      terminus must be explicitly re-set for subsequent catalog actions.
    EOT
    examples <<-'EOT'
      Retrieve and store a catalog:

      $ puppet catalog download

      API example:

          Puppet::Face[:plugin, '0.0.1'].download
          Puppet::Face[:facts, '0.0.1'].upload
          Puppet::Face[:catalog, '0.0.1'].download
          # ...
    EOT
    when_invoked do |_options|
      Puppet::Resource::Catalog.indirection.terminus_class = :rest
      Puppet::Resource::Catalog.indirection.cache_class = nil
      facts = Puppet::Face[:facts, '0.0.1'].find(Puppet[:certname])
      catalog = nil
      retrieval_duration = thinmark do
        catalog = Puppet::Face[:catalog, '0.0.1'].find(Puppet[:certname],
                                                       { facts_for_catalog: facts })
      end
      catalog.retrieval_duration = retrieval_duration
      catalog.write_class_file

      Puppet::Resource::Catalog.indirection.terminus_class = :yaml
      Puppet::Face[:catalog, "0.0.1"].save(catalog)
      Puppet.notice "Saved catalog for #{Puppet[:certname]} to #{Puppet::Resource::Catalog.indirection.terminus.path(Puppet[:certname])}"
      nil
    end
  end
end
