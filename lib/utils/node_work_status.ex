defmodule NodeWorkStatus do
  @moduledoc """
    To maintain works status of all nodes
  """
  require Logger
  defstruct [:job_name, :node, :complete_time, is_complete: false, row_id: -1]

  def new(schedule) do
    joblist =
      for {id, node, job_name} <- schedule,
          into: %{},
          do: {id, %NodeWorkStatus{job_name: job_name, node: node}}

    %{jobs: joblist, start_by: node(), time: Time.utc_now()}
  end

  def update_status(%{id: id, row: row_id}, %{jobs: jobs} = status) do
    job = jobs[id]
    %{status | jobs: %{jobs | id => %{job | row_id: row_id}}}
  end

  def job_complete(id, %{jobs: jobs} = status) do
    job = jobs[id]
    %{status | jobs: %{jobs | id => %{job | is_complete: true, complete_time: Time.utc_now()}}}
  end

  def get_jobs(node, status) do
    for {id, %NodeWorkStatus{node: ^node, job_name: job, row_id: row}} <- status.jobs do
      {id, job, row}
    end
  end

  def get_jobs(reassign_jobs, node, status) do
    nodejobs = for {id, ^node} <- reassign_jobs, do: id

    for {id, %NodeWorkStatus{job_name: job, row_id: row}} <- status.jobs, id in nodejobs do
      {id, job, row}
    end
  end

  def isAllCompleted?(status)do
    Enum.all?(status.jobs,fn {_,job} -> job.is_complete end)
  end

  def print_state(status) do
      state = for n <- :erlang.nodes() ++ [node()], into: %{}, do: {n,[]}
      state = 
      List.foldl(Map.to_list(status.jobs),state,
      fn ({_,job},state) -> 
        old = state[job.node]
        %{state | job.node => [job.job_name | old]} end)
      Logger.info(" Total Jobs #{inspect(length(Map.to_list(status.jobs)))}\n")
      Enum.each(state,fn {node,jobnames} -> 
        Logger.info(" Node : #{inspect(node)} jobs count : #{length(jobnames)} \n 
         Jobs : #{inspect(jobnames)}\n\n")
      end)
  end

  def get_incomplete_jobs(nil), do: []

  def get_incomplete_jobs(status) do
    for {_id, %NodeWorkStatus{node: node, is_complete: false}} <- status.jobs, do: node
  end

  def get_incomplete_jobs(_nodes, nil), do: []

  def get_incomplete_jobs(nodes, status) do
    for {id, %NodeWorkStatus{node: node, is_complete: false}} <- status.jobs,
        node in nodes do
      id
    end
  end

  def reassign(status,jobId,fromNode,toNode)do
    jobs = status.jobs
    %{node: ^fromNode} = job  = jobs[jobId]
    %{status | jobs: %{jobs | jobId => %{job | node: toNode} }}  
  end

  def reassign(jobs, status) do
    newjobs =
      List.foldl(jobs, status.jobs, fn {node, id}, acc ->
        work = acc[id]

        if(work.node != node) do
          %{acc | id => %{work | node: node}}
        else
          acc
        end
      end)

    %{status | jobs: newjobs}
  end
end
