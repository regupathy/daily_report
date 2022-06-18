defmodule NodeWorkStatus do
  @moduledoc """
    To maintain works status of all nodes
  """
  defstruct [:job_name, :node, :complete_time, is_complete: false, row_id: 0]

  def new(schedule) do
    joblist =
      for {id, node, job_name} <- schedule,
          into: %{},
          do: {id, %NodeWorkStatus{job_name: job_name, node: node}}

    %{jobs: joblist, start_by: node(), time: Time.utc_now()}
  end

  def update_status(%{id: id, row: row_id}, status) do
    %{status | id => %NodeWorkStatus{status[id] | row_id: row_id}}
  end

  def job_complete(id, status) do
    %{
      status
      | id => %NodeWorkStatus{status[id] | is_complete: true, complete_time: Time.utc_now()}
    }
  end

  def get_jobs(node, status) do
    for {id, %NodeWorkStatus{node: ^node, job_name: job, row_id: row}} <- status.jobs do
      {id, job,row}
    end
  end

  def get_jobs(reassign_jobs, node, status) do
    nodejobs = for {id,^node} <- reassign_jobs, do: id
    for {id, %NodeWorkStatus{job_name: job,row_id: row}} <- status.jobs, id in nodejobs do
      {id, job,row}
    end
  end

  def get_incomplete_jobs(nodes, status) do
    for {id, %NodeWorkStatus{node: node, is_complete: false} = task} <- status.jobs,
        node not in nodes do
      id
    end
  end

  def reassign(jobs,status) do
      List.foldl(jobs,status,fn({id,node},acc) ->
        work = status.jobs[id]
        status = %{status | jobs: %{status.jobs | id => %{work | node: node}}}
      end)
  end

end
