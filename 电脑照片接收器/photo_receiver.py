"""PENP/1 photo receiver. Python standard library only; fixed direct-LAN profile.
Run photo_receiver.py for GUI, or --console for terminal operation.
"""
from __future__ import annotations
import argparse,base64,datetime,json,socket,struct,threading,time,zlib
from pathlib import Path
MAGIC=b'PENP'; VERSION=1; HEADER=struct.Struct('!4sBBHIHH')
POLL,READ,DONE=1,2,3
NO_PHOTO,META,DATA,BUSY=0x80,0x81,0x82,0x84
BLOCK=1024

def packet(kind:int,epoch=0,offset=0,body=b'',flags=0):
    return HEADER.pack(MAGIC,VERSION,kind,epoch,offset,len(body),flags)+body

def unpack(data):
    if len(data)<HEADER.size:raise ValueError('数据包头不完整')
    magic,version,kind,epoch,offset,n,flags=HEADER.unpack_from(data)
    if magic!=MAGIC or version!=VERSION or len(data)!=HEADER.size+n:
        raise ValueError('数据包版本或长度错误')
    return kind,epoch,offset,flags,data[HEADER.size:]

def png_rgb(width,height,rgb):
    if len(rgb)!=width*height*3:raise ValueError('像素数量不完整，未保存')
    def chunk(tag,data):return struct.pack('!I',len(data))+tag+data+struct.pack('!I',zlib.crc32(tag+data)&0xffffffff)
    rows=b''.join(b'\0'+rgb[y*width*3:(y+1)*width*3] for y in range(height))
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!IIBBBBB',width,height,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(rows,6))+chunk(b'IEND',b'')

def parse_meta(body,flags):
    if len(body)!=32:raise ValueError('照片说明长度错误')
    w,h,total=struct.unpack_from('!HHI',body)
    if not (1<=w<=1280 and 1<=h<=720 and total==w*h*3):raise ValueError('照片尺寸不合法')
    return {'width':w,'height':h,'total_bytes':total,'slots':list(struct.unpack_from('<4I',body,8)),
            'asset_version':struct.unpack_from('!I',body,24)[0],'gamma':bool(flags&1)}

def load_assets(path):
    obj=json.loads(Path(path).read_text(encoding='utf-8'))
    raw=zlib.decompress(base64.b64decode(obj['indices_zlib_base64']))
    if len(raw)!=28672:raise ValueError('贴图资源长度错误')
    check=zlib.crc32(raw+bytes(obj['gamma'])+bytes.fromhex(obj['palette_rgb_hex']))&0xffffffff
    if check!=obj['version']:raise ValueError('贴图资源校验失败')
    obj['indices']=raw;obj['palettes']=bytes.fromhex(obj['palette_rgb_hex']);return obj

def render_photo(raw,meta,assets):
    if len(raw)!=meta['total_bytes']:raise ValueError('照片尚未收齐')
    if assets['version']!=meta['asset_version']:raise ValueError('接收器贴图版本与FPGA不同，请使用同一版资源')
    pixels=bytearray(raw.translate(bytes(assets['gamma'])) if meta['gamma'] else raw)
    width,height=meta['width'],meta['height'];indices=assets['indices'];palettes=assets['palettes']
    for slot in meta['slots']:
        if not slot>>31:continue
        asset=((slot>>28)&4)|(slot&3)
        if asset>=4:raise ValueError('不支持的贴图编号')
        w=min(256,32+2*((slot>>23)&127));h=w if asset<2 else w//2
        left=(slot>>12)&2047;top=(slot>>2)&1023;step=(4194304+w-1)//w
        for yy in range(min(h,max(0,height-top))):
            v=(yy*step)>>(15 if asset==0 else 16)
            for xx in range(min(w,max(0,width-left))):
                u=(xx*step)>>(15 if asset<2 else 16)
                addr=v*128+u if asset==0 else 16384+v*128+u if asset==1 else 24576+(asset-2)*2048+v*64+u
                idx=indices[addr]
                if idx:
                    c=((asset if asset<2 else 2)*64+idx)*3
                    p=((top+yy)*width+left+xx)*3;pixels[p:p+3]=palettes[c:c+3]
    return bytes(pixels)

class PhotoClient:
    def __init__(self,bind='192.168.137.1',target='192.168.137.255',local_port=6001,remote_port=6002,timeout=.25,retries=12,progress=lambda *args:None):
        self.sock=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
        self.sock.setsockopt(socket.SOL_SOCKET,socket.SO_BROADCAST,1)
        self.sock.setsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF,1<<20)
        self.sock.bind((bind,local_port));self.sock.settimeout(timeout)
        self.destination=(target,remote_port);self.timeout=timeout;self.retries=retries;self.progress=progress
        self.last_done=None
    def close(self):self.sock.close()
    def send(self,kind,epoch=0,offset=0):self.sock.sendto(packet(kind,epoch,offset),self.destination)
    def receive(self,deadline):
        while time.monotonic()<deadline:
            self.sock.settimeout(max(.001,deadline-time.monotonic()))
            try:data,peer=self.sock.recvfrom(2048)
            except socket.timeout:return None
            if peer[1]!=self.destination[1]:continue
            try:return unpack(data)
            except ValueError:continue
        return None
    def poll(self):
        self.send(POLL)
        got=self.receive(time.monotonic()+self.timeout)
        if got is None:return None
        kind,epoch,offset,flags,body=got
        if kind==NO_PHOTO:self.progress('status','没有已拍照片');return None
        if kind!=META or offset!=0:return None
        if epoch==self.last_done:self.send(DONE,epoch);return None
        meta=parse_meta(body,flags);meta['epoch']=epoch;return meta
    def download(self,meta):
        epoch=meta['epoch'];result=bytearray(meta['total_bytes']);retries=0
        for offset in range(0,len(result),BLOCK):
            needed=min(BLOCK,len(result)-offset)
            for attempt in range(self.retries):
                self.send(READ,epoch,offset)
                end=time.monotonic()+self.timeout
                while True:
                    got=self.receive(end)
                    if got is None:break
                    kind,e,pos,flags,body=got
                    if kind==DATA and e==epoch and pos==offset and len(body)==needed:
                        result[offset:offset+needed]=body;break
                    if kind==NO_PHOTO:raise RuntimeError('照片已失效，传输取消')
                else:continue
                if got is not None and kind==DATA and e==epoch and pos==offset and len(body)==needed:break
                retries+=1
            else:raise TimeoutError(f'第{offset//BLOCK+1}包多次未收到，未将不完整图像保存为照片；请检查网线并重新发送。')
            if offset%(BLOCK*32)==0 or offset+needed==len(result):self.progress('progress',(offset+needed)/len(result))
        return bytes(result),retries
    def finish(self,epoch):
        for _ in range(3):self.send(DONE,epoch)
        self.last_done=epoch

def run(args,notify,stop):
    client=None
    try:
        assets=load_assets(Path(__file__).with_name('photo_assets.json'))
        folder=Path(args.output).expanduser().resolve();folder.mkdir(parents=True,exist_ok=True)
        client=PhotoClient(args.bind,args.target,args.port,args.board_port,progress=notify)
        notify('status','已就绪：请在FPGA拍照后按发送键')
        while not stop.is_set():
            meta=client.poll()
            if meta is None:stop.wait(.15);continue
            notify('status','正在接收照片，缺包会自动重试…');started=time.monotonic()
            raw,retries=client.download(meta)
            notify('status','正在还原滤镜画面与拍摄时贴图…')
            rgb=render_photo(raw,meta,assets);png=png_rgb(meta['width'],meta['height'],rgb)
            name=datetime.datetime.now().strftime('photo_%Y%m%d_%H%M%S_%f')+f"_{meta['epoch']:04x}"
            path=folder/(name+'.png');temp=path.with_suffix('.part');temp.write_bytes(png);temp.replace(path)
            meta.update({'seconds':round(time.monotonic()-started,3),'retry_count':retries,'image_crc32':f'{zlib.crc32(rgb)&0xffffffff:08x}'})
            path.with_suffix('.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf-8')
            client.finish(meta['epoch']);notify('saved',(str(path),png));notify('status',f"已保存：{path.name}，等待下一次发送")
    except Exception as exc:notify('error',str(exc))
    finally:
        if client:client.close()

def main():
    parser=argparse.ArgumentParser(description='FPGA照片接收器（PENP/1）')
    parser.add_argument('--bind',default='192.168.137.1');parser.add_argument('--target',default='192.168.137.255')
    parser.add_argument('--port',type=int,default=6001);parser.add_argument('--board-port',type=int,default=6002)
    parser.add_argument('--output',default=str(Path(__file__).with_name('received_photos')));parser.add_argument('--console',action='store_true')
    args=parser.parse_args();stop=threading.Event()
    if args.console:
        def show(kind,value):
            if kind!='progress':print(kind,value[0] if kind=='saved' else value,flush=True)
        try:run(args,show,stop)
        except KeyboardInterrupt:stop.set()
        return
    import tkinter as tk
    from tkinter import ttk,messagebox
    import queue,os
    root=tk.Tk();root.title('FPGA 照片接收器');root.geometry('820x650');events=queue.Queue();thread=None
    frame=ttk.Frame(root,padding=18);frame.pack(fill='both',expand=True)
    ttk.Label(frame,text='FPGA 照片接收器',font=('Microsoft YaHei',19)).pack(anchor='w')
    ttk.Label(frame,text=f'电脑网卡：{args.bind}     FPGA：192.168.137.2     端口：{args.port}',padding=(0,10)).pack(anchor='w')
    status=tk.StringVar(value='连接网线、设置电脑有线网卡IP后，点击开始接收。');ttk.Label(frame,textvariable=status,wraplength=770).pack(anchor='w')
    bar=ttk.Progressbar(frame,maximum=100);bar.pack(fill='x',pady=12)
    buttons=ttk.Frame(frame);buttons.pack(fill='x');preview=ttk.Label(frame,text='收到照片后在此预览',anchor='center');preview.pack(fill='both',expand=True,pady=16)
    def begin():
        nonlocal thread
        if thread and thread.is_alive():return
        stop.clear();bar['value']=0;thread=threading.Thread(target=run,args=(args,lambda k,v:events.put((k,v)),stop),daemon=True);thread.start()
    def folder():
        Path(args.output).mkdir(parents=True,exist_ok=True);os.startfile(str(Path(args.output).resolve()))
    ttk.Button(buttons,text='开始接收',command=begin).pack(side='left');ttk.Button(buttons,text='打开照片文件夹',command=folder).pack(side='left',padx=10)
    def update():
        try:
            while True:
                kind,value=events.get_nowait()
                if kind=='progress':bar['value']=100*value
                elif kind=='saved':
                    image=tk.PhotoImage(data=base64.b64encode(value[1]));factor=max(1,(image.width()+759)//760,(image.height()+419)//420)
                    preview.image=image.subsample(factor);preview.configure(image=preview.image,text='');bar['value']=100
                elif kind=='error':status.set('接收未完成：'+value);messagebox.showerror('接收提示',value)
                else:status.set(value)
        except queue.Empty:pass
        root.after(100,update)
    root.protocol('WM_DELETE_WINDOW',lambda:(stop.set(),root.destroy()));update();root.mainloop()
if __name__=='__main__':main()
