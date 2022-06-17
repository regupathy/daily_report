defmodule AppNodeHandler do

    use GenServer

    @impl true
    def init(_opts)do    
        {:ok,%{}}
    end

    @impl true
    def handle_call(_msg,_from,state)do
        {:reply,:ok,state}
    end

    @impl true
    def handle_cast(_msg,state)do
        {:noreply,state}
    end


end
