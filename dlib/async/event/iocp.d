/*
Copyright (c) 2016 Timur Gafarov 

Boost Software License - Version 1.0 - August 17th, 2003

Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

/**
 * Copyright: Eugene Wissner 2016-.
 * License: $(LINK2 boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: Eugene Wissner
 */
module dlib.async.event.iocp;

version (Windows):

import dlib.container.buffer;
import dlib.async.loop;
import dlib.async.protocol;
import dlib.async.transport;
import dlib.async.watcher;
import dlib.memory;
import dlib.memory.mmappool;
import dlib.network.socket;
import core.sys.windows.basetyps;
import core.sys.windows.mswsock;
import core.sys.windows.winbase;
import core.sys.windows.windef;
import core.sys.windows.winsock2;

class IOCPStreamTransport : StreamTransport
{
    private OverlappedConnectedSocket socket_;

    private WriteBuffer input;

    /**
     * Creates new completion port transport.
     * Params:
     *     socket   = Socket.
     */
    this(OverlappedConnectedSocket socket)
    in
    {
        assert(socket !is null);
    }
    body
    {
        socket_ = socket;
        input = MmapPool.instance.make!WriteBuffer();
    }

    ~this()
    {
        MmapPool.instance.dispose(input);
    }

    @property inout(OverlappedConnectedSocket) socket() inout pure nothrow @safe @nogc
    {
        return socket_;
    }

    /**
     * Write some data to the transport.
     *
     * Params:
     *     data = Data to send.
     */
    void write(ubyte[] data)
    {
        immutable empty = input.length == 0;
        input ~= data;
        if (empty)
        {
            SocketState overlapped;
            try
            {
                overlapped = MmapPool.instance.make!SocketState;
                socket.beginSend(input[], overlapped);
            }
            catch (SocketException e)
            {
                MmapPool.instance.dispose(overlapped);
                MmapPool.instance.dispose(e);
            }
        }
    }
}

class IOCPLoop : Loop
{
    protected HANDLE completionPort;

    protected OVERLAPPED overlap;

    /**
     * Initializes the loop.
     */
    this()
    {
        super();

        completionPort = CreateIoCompletionPort(INVALID_HANDLE_VALUE, NULL, 0, 0);
        if (!completionPort)
        {
            throw defaultAllocator.make!BadLoopException("Creating completion port failed");
        }
    }

    /**
     * Should be called if the backend configuration changes.
     *
     * Params:
     *     watcher   = Watcher.
     *     oldEvents = The events were already set.
     *     events    = The events should be set.
     *
     * Returns: $(D_KEYWORD true) if the operation was successful.
     */
    override protected bool reify(ConnectionWatcher watcher,
                                  EventMask oldEvents,
                                  EventMask events)
    {
        SocketState overlapped;
        if (!(oldEvents & Event.accept) && (events & Event.accept))
        {
            auto socket = cast(OverlappedStreamSocket) watcher.socket;
            assert(socket !is null);

            if (CreateIoCompletionPort(cast(HANDLE) socket.handle,
                                       completionPort,
                                       cast(ULONG_PTR) (cast(void*) watcher),
                                       0) !is completionPort)
            {
                return false;
            }

            try
            {
                overlapped = MmapPool.instance.make!SocketState;
                socket.beginAccept(overlapped);
            }
            catch (SocketException e)
            {
                MmapPool.instance.dispose(overlapped);
                defaultAllocator.dispose(e);
                return false;
            }
        }
        if (!(oldEvents & Event.read) && (events & Event.read)
            || !(oldEvents & Event.write) && (events & Event.write))
        {
            auto io = cast(IOWatcher) watcher;
            assert(io !is null);

            auto transport = cast(IOCPStreamTransport) io.transport;
            assert(transport !is null);

            if (CreateIoCompletionPort(cast(HANDLE) transport.socket.handle,
                                       completionPort,
                                       cast(ULONG_PTR) (cast(void*) watcher),
                                       0) !is completionPort)
            {
                return false;
            }

            // Begin to read
            if (!(oldEvents & Event.read) && (events & Event.read))
            {
                try
                {
                    overlapped = MmapPool.instance.make!SocketState;
                    transport.socket.beginReceive(io.output[], overlapped);
                }
                catch (SocketException e)
                {
                    MmapPool.instance.dispose(overlapped);
                    defaultAllocator.dispose(e);
                    return false;
                }
            }
        }
        return true;
    }

    /**
     * Does the actual polling.
     */
    override protected void poll()
    {
        DWORD lpNumberOfBytes;
        ULONG_PTR key;
        LPOVERLAPPED overlap;
        immutable timeout = cast(immutable int) blockTime.total!"msecs";

        auto result = GetQueuedCompletionStatus(completionPort,
                                                &lpNumberOfBytes,
                                                &key,
                                                &overlap,
                                                timeout);
        if (result == FALSE && overlap == NULL)
        {
            return; // Timeout
        }

        auto overlapped = (cast(SocketState) ((cast(void*) overlap) - 8));
        assert(overlapped !is null);
        scope (failure)
        {
            MmapPool.instance.dispose(overlapped);
        }

        switch (overlapped.event)
        {
            case OverlappedSocketEvent.accept:
                auto connection = cast(ConnectionWatcher) (cast(void*) key);
                assert(connection !is null);

                auto listener = cast(OverlappedStreamSocket) connection.socket;
                assert(listener !is null);

                auto socket = listener.endAccept(overlapped);
                auto transport = MmapPool.instance.make!IOCPStreamTransport(socket);
                auto io = MmapPool.instance.make!IOWatcher(transport, connection.protocol);

                connection.incoming.insertBack(io);

                reify(io, EventMask(Event.none), EventMask(Event.read, Event.write));

                swapPendings.insertBack(connection);
                listener.beginAccept(overlapped);
                break;
            case OverlappedSocketEvent.read:
                auto io = cast(IOWatcher) (cast(void*) key);
                assert(io !is null);
                if (!io.active)
                {
                    MmapPool.instance.dispose(io);
                    MmapPool.instance.dispose(overlapped);
                    return;
                }

                auto transport = cast(IOCPStreamTransport) io.transport;
                assert(transport !is null);

                int received;
                SocketException exception;
                try
                {
                    received = transport.socket.endReceive(overlapped);
                }
                catch (SocketException e)
                {
                    exception = e;
                }
                if (transport.socket.disconnected)
                {
                    // We want to get one last notification to destroy the watcher
                    transport.socket.beginReceive(io.output[], overlapped);
                    kill(io, exception);
                }
                else if (received > 0)
                {
                    immutable full = io.output.free == received;

                    io.output += received;
                    // Receive was interrupted because the buffer is full. We have to continue
                    if (full)
                    {
                        transport.socket.beginReceive(io.output[], overlapped);
                    }
                    swapPendings.insertBack(io);
                }
                break;
            case OverlappedSocketEvent.write:
                auto io = cast(IOWatcher) (cast(void*) key);
                assert(io !is null);

                auto transport = cast(IOCPStreamTransport) io.transport;
                assert(transport !is null);

                transport.input += transport.socket.endSend(overlapped);
                if (transport.input.length)
                {
                    transport.socket.beginSend(transport.input[], overlapped);
                }
                else
                {
                    transport.socket.beginReceive(io.output[], overlapped);
                }
                break;
            default:
                assert(false, "Unknown event");
        }
    }
}
